from std.math import cos, pi, sin

from canvas.text.font_cache import FontCache
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget

from dataviz.core.array_like import (
    _materialize_nested_scalar_list,
    _materialize_scalar_list,
)
from dataviz.core.color_scale import categorical_palette_for
from dataviz.core.mark import Mark
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
from dataviz.core.theme import Theme


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
    """Draw evenly spaced polar grid rings and spokes without labels."""
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
    named series each get a `categorical_palette_for(theme)` color and a
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

        var palette = categorical_palette_for(theme)
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
    where a circular layout is the natural fit. For several named
    series on one angular axis, call `polar(angle, series_names,
    series_values)` -- the overload below -- which is the same chart
    with a legend.

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
        from std.math import pi

        from dataviz import polar
        from dataviz import save

        def main() raises:
            var angle = List[Float64]()
            for hour in range(25):
                angle.append(2.0 * pi * Float64(hour) / 24.0)

            # Illustrative hourly electricity demand (GW); repeat midnight at
            # hour 24 so the daily profile closes around the clock.
            var demand: List[Float64] = [
                22.0, 20.5, 19.4, 18.8, 19.1, 21.7,
                26.8, 31.5, 34.2, 35.8, 36.9, 37.4,
                36.8, 36.1, 35.7, 36.4, 39.2, 43.8,
                46.1, 44.7, 40.3, 34.8, 29.1, 25.0, 22.0,
            ]

            var c = polar(
                angle,
                demand,
                title="Illustrative Weekday Electricity Demand (GW)",
            )
            save(c, "docs/src/examples/out_polar.svg")
        ```

    Example (Several Series):
        ```mojo
        from std.math import pi

        from dataviz import polar
        from dataviz import save

        def main() raises:
            var angle = List[Float64]()
            for hour in range(25):
                angle.append(2.0 * pi * Float64(hour) / 24.0)

            # Illustrative station entries (thousands) by hour. The final value
            # repeats midnight so each profile closes around the clock.
            var weekday: List[Float64] = [
                1.2, 0.7, 0.4, 0.3, 0.5, 1.8,
                5.6, 10.8, 13.2, 9.4, 6.1, 5.3,
                5.0, 5.2, 5.8, 7.1, 9.6, 12.7,
                14.1, 11.3, 7.8, 5.0, 3.1, 2.0, 1.2,
            ]
            var weekend: List[Float64] = [
                2.0, 1.3, 0.8, 0.5, 0.4, 0.6,
                1.1, 2.2, 3.8, 5.5, 7.1, 8.4,
                9.0, 9.4, 9.8, 10.1, 10.5, 10.7,
                9.9, 8.6, 7.0, 5.2, 3.7, 2.7, 2.0,
            ]
            var names: List[String] = ["Weekday", "Weekend"]
            var values: List[List[Float64]] = [
                weekday.copy(), weekend.copy(),
            ]

            var c = polar(
                angle,
                names,
                values,
                title="Illustrative Hourly Transit Demand (thousands)",
            )
            save(c, "docs/src/examples/out_polar_several_series.svg")
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
    `DType` overload (continuous.mojo). `angle`/`radius` share one dtype.
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


def polar(
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
    """`polar()` for several named series sharing one angular axis: one
    trace per name, one radius scale across all of them, and a legend
    keyed by `series_names`. The single-series form is the overload
    above (#110).

    `Mark.POLAR` over `Plot.encode_polar_series()`.

    Args:
        angle: Radians, used exactly as given and unwrapped -- shared
            by every series.
        series_names: One trace per name, used as the legend key.
        series_values: `series_values[j]` is `series_names[j]`'s
            radius per angle; every value must be non-negative, and
            every series shares one radius scale.
        theme: Full styling knobs beyond this function's own
            arguments.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title; empty for none.
        subtitle: Chart subtitle; empty for none.
        x_title: X-axis title; empty for none.
        y_title: Y-axis title; empty for none.

    Returns:
        The finished `Plot`, ready to `render()` or `save()`.

    Raises:
        Error: A series does not match `angle`'s length or holds a
            negative radius (checked at render time).
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


def polar[
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
    """The multi-series `polar()` generalized over `series_values`'
    element type; see `scatter()`'s `DType` overload (continuous.mojo).
    `angle` stays concrete. Delegates to the concrete overload above.
    """
    return polar(
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
