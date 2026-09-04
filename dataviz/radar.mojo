from std.math import cos, pi

from canvas.fill_rule import FillRule
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget
from canvas.text.render import TextAlign
from dataviz.plot import _LazyFontCache

from dataviz.array_like import (
    _materialize_nested_scalar_list,
    _materialize_scalar_list,
)
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_legend,
    _dynamic_legend_width,
    _lighten,
    _finished,
    _require_non_empty,
)
from dataviz.polar import _polar_point
from dataviz.theme import Theme


struct _RadarData(Copyable, Movable):
    """One named indicator (axis) per entry with its max, plus one or more
    named series each with a value per indicator, for `Mark.RADAR`. See
    `encode_radar()`. Stored on `Plot._radar`.
    """

    var indicators: List[String]
    var max_values: List[Float64]
    var series_names: List[String]
    var series_values: List[List[Float64]]

    def __init__(out self):
        self.indicators = List[String]()
        self.max_values = List[Float64]()
        self.series_names = List[String]()
        self.series_values = List[List[Float64]]()


def _draw_radar_grid[
    T: DrawTarget
](
    mut target: T,
    cx: Float64,
    cy: Float64,
    max_radius: Float64,
    n: Int,
    theme: Theme,
    grid_rings: Int,
) raises:
    """The radar coordinate system: `n` spokes from the center out to
    `max_radius` (one per indicator, via `_polar_point`), plus
    `grid_rings` concentric web rings, each a straight-edged `n`-sided
    polygon connecting every spoke at that ring's radius fraction.
    Polygons rather than circles (as in `polar.mojo`'s `_draw_polar_grid`)
    because a radar's axes are discrete; this matches ECharts' default
    `shape: 'polygon'`.
    """
    for i in range(n):
        var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
        var tip = _polar_point(cx, cy, angle, max_radius)
        target.draw_line_aa(
            Int(cx), Int(cy), Int(tip.x), Int(tip.y), theme.gridline_color
        )

    for ring in range(1, grid_rings + 1):
        var r = max_radius * Float64(ring) / Float64(grid_rings)
        var web = Path()
        for i in range(n):
            var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
            var pt = _polar_point(cx, cy, angle, r)
            if i == 0:
                web.move_to(pt.x, pt.y)
            else:
                web.line_to(pt.x, pt.y)
        web.close()
        target.stroke_path_aa(web, theme.gridline_color)


def _render_radar[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: _LazyFontCache,
) raises -> _RenderResult:
    """Render a `Mark.RADAR` plot: `encode_radar()`'s `indicators` (one
    spoke each, evenly spaced, starting at 12 o'clock and sweeping
    clockwise), each with its own `max_values`, and one or more series
    (name + one value per indicator) drawn as a closed polygon each with
    straight `line_to` segments.

    Values are not clamped to `[0, max_values[i]]`: a value past its axis
    max draws past the outer ring. Each axis has an independent max
    (unlike `Mark.POLAR`'s single shared radius domain), so differently
    scaled dimensions share one grid.

    Each series polygon is filled with the `_lighten`'d palette color
    (`theme.radar_fill_alpha`) and stroked with the full palette color,
    both from the same path; there is no flag to skip the fill, since
    overlapping unfilled outlines are unreadable. Legend keyed by
    `series_names`, drawn whenever `Theme.show_legend` is on.
    """
    _require_non_empty(len(plot._radar.indicators), "Plot.encode_radar()")

    var theme = plot._theme
    var text_requests = List[_TextRequest]()

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _dynamic_legend_width(
        plot._radar.series_names, sc.legend_swatch_size, sc, cache=cache
    ) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = (
        Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    )

    var n = len(plot._radar.indicators)
    if theme.show_gridlines:
        _draw_radar_grid(
            target,
            cx,
            cy,
            max_radius,
            n,
            theme,
            plot._mark_style.radar_grid_rings,
        )

    var palette = default_categorical_palette()
    for s in range(len(plot._radar.series_values)):
        var values = plot._radar.series_values[s].copy()
        var color = palette[s % len(palette)]
        var poly = Path()
        for i in range(n):
            var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
            var frac = (
                values[i]
                / plot._radar.max_values[i] if plot._radar.max_values[i]
                > 0.0 else 0.0
            )
            var pt = _polar_point(cx, cy, angle, max_radius * frac)
            if i == 0:
                poly.move_to(pt.x, pt.y)
            else:
                poly.line_to(pt.x, pt.y)
        poly.close()
        target.fill_path_aa(
            poly,
            _lighten(color, theme.radar_fill_alpha),
            fill_rule=FillRule.NONZERO,
        )
        target.stroke_path_aa(poly, color, sc.line_width)

    # Axis labels just outside each spoke's tip, aligned by which side of
    # center the tip falls on (LEFT for the right half, RIGHT for the left
    # half, CENTER for top/bottom).
    for i in range(n):
        var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
        var tip = _polar_point(
            cx, cy, angle, max_radius + Float64(sc.label_gap)
        )
        var c = cos(angle)
        var align = TextAlign.CENTER
        if c > 0.3:
            align = TextAlign.LEFT
        elif c < -0.3:
            align = TextAlign.RIGHT
        text_requests.append(
            _TextRequest(
                Int(tip.x),
                Int(tip.y),
                plot._radar.indicators[i],
                theme.text_color,
                sc.font_size,
                align,
                theme.font_family,
            )
        )

    if show_legend:
        _draw_legend(
            target,
            text_requests,
            plot._radar.series_names,
            palette,
            plot_x1 + sc.margin_right,
            plot_y0,
            theme,
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def radar(
    indicators: List[String],
    max_values: List[Float64],
    series_names: List[String],
    series_values: List[List[Float64]],
    grid_rings: Int = 4,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A radar/spider chart: one axis per indicator radiating from a
    shared center, with each series drawn as a polygon connecting its
    values, for comparing several items across the same set of metrics
    at once.

    `Mark.RADAR` over `Plot.encode_radar()`'s shape: `indicators` (one
    spoke per name, each with its `max_values` entry) and one polygon per
    series (`series_names` + a value per indicator in `series_values`).
    See `_render_radar`.

    Args:
        indicators: One spoke per entry, in the given order.
        max_values: Each spoke's own independent maximum, paired with
            `indicators[i]`.
        series_names: One polygon per name, used as the legend key.
        series_values: `series_values[j]` is `series_names[j]`'s
            value per indicator.
        grid_rings: How many concentric web rings to draw; defaults to `4`.
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
        from dataviz import radar
        from dataviz.plot import save

        def main() raises:
            var indicators: List[String] = ["Attack", "Defense", "Speed", "Stamina", "Skill"]
            var max_values: List[Float64] = [100.0, 100.0, 100.0, 100.0, 100.0]
            var series_names: List[String] = ["Team A", "Team B"]
            var series_values: List[List[Int]] = [
                [90, 60, 80, 70, 85],
                [65, 85, 55, 90, 60],
            ]

            var c = radar(indicators, max_values, series_names, series_values)
            save(c, "docs/src/examples/out_radar.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_radar(grid_rings=grid_rings)
        .encode_radar(
            indicators=indicators,
            max_values=max_values,
            series_names=series_names,
            series_values=series_values,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def radar[
    dtype: DType
](
    indicators: List[String],
    max_values: List[Float64],
    series_names: List[String],
    series_values: List[List[Scalar[dtype]]],
    grid_rings: Int = 4,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`radar()` generalized over numeric element type for `series_values`,
    via `_materialize_nested_scalar_list` (array_like.mojo); see
    `scatter()`'s `DType` overload (plot.mojo). `max_values` stays
    concrete here (the overload below covers it). Delegates to the
    concrete overload above.
    """
    return radar(
        indicators,
        max_values,
        series_names,
        _materialize_nested_scalar_list(series_values),
        grid_rings=grid_rings,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )


def radar[
    dtype: DType
](
    indicators: List[String],
    max_values: List[Scalar[dtype]],
    series_names: List[String],
    series_values: List[List[Float64]],
    grid_rings: Int = 4,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`radar()` generalized over numeric element type for `max_values`, via
    `_materialize_scalar_list`. `series_values` stays concrete here.
    Delegates to the concrete overload above.
    """
    return radar(
        indicators,
        _materialize_scalar_list(max_values),
        series_names,
        series_values,
        grid_rings=grid_rings,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
