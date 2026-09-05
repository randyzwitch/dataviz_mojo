from std.math import cos, pi, sin

from canvas.text.font_cache import FontCache
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import (
    _materialize_nested_scalar_list,
    _materialize_scalar_list,
)
from dataviz.color_scale import default_categorical_palette
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _LegendLayout,
    _draw_legend_at,
    _legend_layout,
    _finished,
    _require_non_empty,
)
from dataviz.theme import Theme


struct _PolarData(Copyable, Movable):
    """One (angle, radius) pair per row (`encode_polar()`), or a shared
    `angle` plus one or more named series (`encode_polar_series()`;
    `series_names` non-empty is what `_render_polar` branches on, and
    `radius` stays empty then), for `Mark.POLAR`. Stored on `Plot._polar`.
    """

    var angle: List[Float64]
    var radius: List[Float64]
    var series_names: List[String]
    var series_radius: List[List[Float64]]

    def __init__(out self):
        self.angle = List[Float64]()
        self.radius = List[Float64]()
        self.series_names = List[String]()
        self.series_radius = List[List[Float64]]()


struct _PolarPoint(Movable):
    """`_polar_point`'s return value."""

    var x: Float64
    var y: Float64

    def __init__(out self, x: Float64, y: Float64):
        self.x = x
        self.y = y


def _polar_point(
    cx: Float64, cy: Float64, angle: Float64, radius: Float64
) -> _PolarPoint:
    """Angle/radius to pixel (x, y), the shared primitive every polar mark
    reduces to. `angle=0` is 3 o'clock; increasing `angle` sweeps
    clockwise (pixel y increases downward), the same convention
    `Mark.ARC`/`CHORD`/`NIGHTINGALE`/`POLAR_BAR` use. `radius` is a pixel
    distance from `(cx, cy)`, already scaled by the caller.
    """
    return _PolarPoint(cx + radius * cos(angle), cy + radius * sin(angle))


def _draw_polar_grid[
    T: DrawTarget
](
    mut target: T,
    cx: Float64,
    cy: Float64,
    max_radius: Float64,
    theme: Theme,
    grid_rings: Int,
    grid_spokes: Int,
) raises:
    """The polar coordinate system: `grid_rings` evenly spaced concentric
    circles plus `grid_spokes` radial lines from the center out to
    `max_radius`, in `theme.gridline_color`. No tick labels; a label
    placed around a circle is typesetting this package has no machinery
    for.

    Each ring is one `draw_circle_aa`. It used to be a `Path` with a full
    `arc_to` sweep, stroked -- the trait had no circle outline that took
    a sub-pixel centre and radius, and a ring's radius is
    `max_radius * i / grid_rings`, so snapping it to whole pixels was not
    an option (#258). canvas_mojo 0.16.0 put that overload on the trait,
    so the workaround is gone.
    """
    for i in range(1, grid_rings + 1):
        var r = max_radius * Float64(i) / Float64(grid_rings)
        target.draw_circle_aa(cx, cy, r, theme.gridline_color)

    for i in range(grid_spokes):
        var angle = 2.0 * pi * Float64(i) / Float64(grid_spokes)
        var tip = _polar_point(cx, cy, angle, max_radius)
        target.draw_line_aa(
            Int(cx), Int(cy), Int(tip.x), Int(tip.y), theme.gridline_color
        )


def _render_polar[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a `Mark.POLAR` plot: `encode_polar()`'s `angle`/`radius` pairs
    (or `encode_polar_series()`'s shared `angle` plus several named
    series), connected in row order by one stroked polyline per series
    with no smoothing, plus a small filled circle at each point, over
    `_draw_polar_grid`'s coordinate system.

    `angle` is used as given, in radians, unscaled and unwrapped: values
    beyond `2*pi` spiral outward rather than overlapping. `radius` is
    scaled linearly from `[0, max(radius)]` to `[0, max_radius]`, always
    zero-anchored at the center. Every `radius` value must be
    non-negative.

    A single series draws in `theme.mark_color` with no legend. Several
    named series each get a `default_categorical_palette()` color and a
    legend keyed by `series_names` (when `Theme.show_legend` is on), and
    share one radius scale with `max(radius)` computed across every
    series.
    """
    var is_multi = len(plot._polar.series_names) > 0
    if is_multi:
        if len(plot._polar.series_radius) != len(plot._polar.series_names):
            raise Error(
                "Plot.encode_polar_series(): series_names and series_values"
                " must have the same length (got "
                + String(len(plot._polar.series_names))
                + " and "
                + String(len(plot._polar.series_radius))
                + ")"
            )
        for values in plot._polar.series_radius:
            if len(values) != len(plot._polar.angle):
                raise Error(
                    "Plot.encode_polar_series(): every series must have the"
                    " same length as angle (got "
                    + String(len(values))
                    + " and "
                    + String(len(plot._polar.angle))
                    + ")"
                )
            for r in values:
                if r < 0.0:
                    raise Error(
                        "Plot: Mark.POLAR radius values must be non-negative"
                        " (got "
                        + String(r)
                        + ")"
                    )
    else:
        if len(plot._polar.angle) != len(plot._polar.radius):
            raise Error(
                "Plot.encode_polar(): angle and radius must have the same"
                " length (got "
                + String(len(plot._polar.angle))
                + " and "
                + String(len(plot._polar.radius))
                + ")"
            )
        for r in plot._polar.radius:
            if r < 0.0:
                raise Error(
                    "Plot: Mark.POLAR radius values must be non-negative (got "
                    + String(r)
                    + ")"
                )

    var theme = plot._theme
    _require_non_empty(
        len(plot._polar.angle), "Plot.encode_polar()/encode_polar_series()"
    )
    var text_requests = List[_TextRequest]()
    var sc = _Scaled(theme)
    var show_legend = is_multi and theme.show_legend
    var legend = _legend_layout(
        plot._polar.series_names,
        sc.legend_swatch_size,
        sc,
        theme,
        ox1 - ox0,
        cache=cache,
    ) if show_legend else _LegendLayout()

    var plot_x0 = ox0 + sc.margin_left + legend.left
    var plot_y0 = oy0 + sc.margin_top + legend.top
    var plot_x1 = ox1 - sc.margin_right - legend.right
    var plot_y1 = oy1 - sc.margin_bottom - legend.bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = (
        Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    )

    if theme.show_gridlines:
        _draw_polar_grid(
            target,
            cx,
            cy,
            max_radius,
            theme,
            plot._mark_style.polar_grid_rings,
            plot._mark_style.polar_grid_spokes,
        )

    if is_multi:
        var max_r = 0.0
        for values in plot._polar.series_radius:
            for r in values:
                if r > max_r:
                    max_r = r

        var palette = default_categorical_palette()
        for s in range(len(plot._polar.series_radius)):
            var values = plot._polar.series_radius[s].copy()
            var color = palette[s % len(palette)]
            var path = Path()
            for i in range(len(plot._polar.angle)):
                var radius_px = (
                    max_radius * (values[i] / max_r) if max_r > 0.0 else 0.0
                )
                var pt = _polar_point(cx, cy, plot._polar.angle[i], radius_px)
                if i == 0:
                    path.move_to(pt.x, pt.y)
                else:
                    path.line_to(pt.x, pt.y)
            target.stroke_path_aa(path, color, sc.line_width)
            for i in range(len(plot._polar.angle)):
                var radius_px = (
                    max_radius * (values[i] / max_r) if max_r > 0.0 else 0.0
                )
                var pt = _polar_point(cx, cy, plot._polar.angle[i], radius_px)
                target.fill_circle_aa(
                    Int(pt.x), Int(pt.y), Int(sc.point_radius), color
                )

        if show_legend:
            _draw_legend_at(
                target,
                text_requests,
                plot._polar.series_names,
                palette,
                legend,
                plot_x0,
                plot_y0,
                plot_x1,
                plot_y1,
                theme,
            )
    else:
        var max_r = 0.0
        for r in plot._polar.radius:
            if r > max_r:
                max_r = r

        var path = Path()
        for i in range(len(plot._polar.angle)):
            var radius_px = (
                max_radius * (plot._polar.radius[i] / max_r) if max_r
                > 0.0 else 0.0
            )
            var pt = _polar_point(cx, cy, plot._polar.angle[i], radius_px)
            if i == 0:
                path.move_to(pt.x, pt.y)
            else:
                path.line_to(pt.x, pt.y)
        target.stroke_path_aa(path, theme.mark_color, sc.line_width)

        for i in range(len(plot._polar.angle)):
            var radius_px = (
                max_radius * (plot._polar.radius[i] / max_r) if max_r
                > 0.0 else 0.0
            )
            var pt = _polar_point(cx, cy, plot._polar.angle[i], radius_px)
            target.fill_circle_aa(
                Int(pt.x), Int(pt.y), Int(sc.point_radius), theme.mark_color
            )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def polar(
    angle: List[Float64],
    radius: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A polar-coordinate line plot: a line series where `angle` and
    `radius` place each point around a circle rather than on x/y axes,
    for cyclical data (compass headings, time of day, seasonal phase)
    where a circular layout is the natural fit.

    `Mark.POLAR` over `angle` (radians, used as given; values beyond
    `2*pi` spiral outward rather than wrapping) and `radius` (linearly
    scaled from `[0, max(radius)]`, zero-anchored at the center; every
    value must be non-negative). See `_render_polar`.

    Args:
        angle: Radians, used exactly as given and unwrapped -- values
            beyond `2*pi` spiral outward rather than overlapping.
        radius: Linearly scaled from `[0, max(radius)]`, always
            zero-anchored at the chart's center; every value must be
            non-negative.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from std.math import pi, sin

        from dataviz import polar
        from dataviz.plot import save

        def main() raises:
            var angle = List[Float64]()
            var radius = List[Float64]()
            var steps = 200
            for i in range(steps + 1):
                var theta = 2.0 * pi * Float64(i) / Float64(steps)
                var r = sin(2.0 * theta)
                # A negative r has no polar meaning on its own -- fold it into
                # the opposite direction (theta + pi) instead, the standard
                # way a signed polar radius is plotted, so the curve's negative lobes still draw rather than getting clipped by
                # encode_polar()'s non-negative-radius validation.
                if r < 0.0:
                    angle.append(theta + pi)
                    radius.append(-r)
                else:
                    angle.append(theta)
                    radius.append(r)

            var c = polar(angle, radius)
            save(c, "docs/src/examples/out_polar.svg")
        ```
    """
    var plot = Plot().mark_polar().encode_polar(angle=angle, radius=radius)
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def polar[
    dtype: DType
](
    angle: List[Scalar[dtype]],
    radius: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`polar()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). `angle`/`radius` share one dtype.
    Delegates to the concrete overload above.
    """
    return polar(
        _materialize_scalar_list(angle),
        _materialize_scalar_list(radius),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )


def polar_series(
    angle: List[Float64],
    series_names: List[String],
    series_values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A multi-series polar-coordinate line plot: `polar()`'s single-series
    shape extended to several named series sharing one angular axis, for
    comparing multiple cyclical series at once.

    `Mark.POLAR` over `Plot.encode_polar_series()`'s shared `angle` plus
    one or more named series (`series_names` + `series_values`, one radius
    value per series per angle), sharing one radius scale and a legend
    keyed by `series_names`. See `_render_polar`.

    Args:
        angle: Radians, used exactly as given and unwrapped -- shared
            by every series.
        series_names: One trace per name, used as the legend key.
        series_values: `series_values[j]` is `series_names[j]`'s
            radius per angle; every value must be non-negative, and
            every series shares one radius scale (`max(radius)`
            computed across all of them together).
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from std.math import pi

        from dataviz import polar_series
        from dataviz.plot import save

        def main() raises:
            var angle = List[Float64]()
            for i in range(12):
                angle.append(2.0 * pi * Float64(i) / 12.0)

            var names: List[String] = ["Miami", "Phoenix"]
            var miami: List[Int] = [68, 69, 72, 76, 80, 83, 84, 85, 84, 80, 74, 69]
            var phoenix: List[Int] = [57, 61, 66, 75, 84, 95, 97, 95, 90, 78, 65, 56]
            var values: List[List[Int]] = [miami.copy(), phoenix.copy()]

            var c = polar_series(angle, names, values)
            save(c, "docs/src/examples/out_polar_series.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_polar()
        .encode_polar_series(
            angle=angle, series_names=series_names, series_values=series_values
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def polar_series[
    dtype: DType
](
    angle: List[Float64],
    series_names: List[String],
    series_values: List[List[Scalar[dtype]]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`polar_series()` generalized over numeric element type for
    `series_values`, via `_materialize_nested_scalar_list`
    (array_like.mojo); see `scatter()`'s `DType` overload (plot.mojo).
    `angle` stays concrete. Delegates to the concrete overload above.
    """
    return polar_series(
        angle,
        series_names,
        _materialize_nested_scalar_list(series_values),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
