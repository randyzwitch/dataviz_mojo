from std.math import cos, pi

from canvas_mojo.color import Color
from canvas_mojo.path import Path
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas
from canvas_mojo.text.render import TextAlign

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_legend,
    _dynamic_legend_width,
    _empty_result,
    _lighten,
    _rendered,
)
from dataviz_mojo.polar import _polar_point
from dataviz_mojo.theme import Theme

# How many evenly-spaced "web" rings the polygon grid draws -- the
# same fixed-constant reasoning `polar.mojo`'s own `_POLAR_GRID_RINGS`
# already gives, unrelated to it only because a radar grid is
# genuinely a different shape (a straight-edged polygon per ring, not
# a circle -- see `_draw_radar_grid`'s own docstring).
comptime _RADAR_GRID_RINGS = 4


def _draw_radar_grid[
    T: DrawTarget
](mut target: T, cx: Float64, cy: Float64, max_radius: Float64, n: Int, theme: Theme) raises:
    """The radar coordinate system: `n` straight spokes from the
    center out to `max_radius` (one per indicator axis, `_polar_point`
    at each axis's own angle), plus `_RADAR_GRID_RINGS` concentric
    "web" rings -- each ring a straight-edged `n`-sided polygon
    connecting every spoke's own tip at that ring's radius fraction,
    *not* a circle the way `polar.mojo`'s own `_draw_polar_grid` rings
    are. This is deliberate, not a missed reuse opportunity: a radar
    chart's own axes are discrete (one per named indicator, not a
    continuous angle), so there's no meaningful position *between*
    two spokes for a circular ring to pass through that isn't already
    implied by straight-line interpolation between them -- the
    standard "polygon grid" reading every radar chart (ECharts
    included, its own default `shape: 'polygon'`) uses.
    """
    for i in range(n):
        var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
        var tip = _polar_point(cx, cy, angle, max_radius)
        target.draw_line_aa(Int(cx), Int(cy), Int(tip.x), Int(tip.y), theme.gridline_color)

    for ring in range(1, _RADAR_GRID_RINGS + 1):
        var r = max_radius * Float64(ring) / Float64(_RADAR_GRID_RINGS)
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
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.RADAR` plot: `encode_radar()`'s own named
    `indicators` (one spoke each, evenly spaced, starting at 12
    o'clock and sweeping clockwise -- the same convention every other
    polar mark in this package shares) with a per-indicator own
    `max_values`, and one or more `series` (name + one value per
    indicator) drawn as a closed polygon each: a straight `line_to`
    from one indicator's own point to the next, back to the first, no
    smoothing (the same "the shape *is* the data" stance `Mark.POLAR`
    already takes for its own polyline).

    Each indicator's own value is *not* clamped to `[0, max_values[i]]`
    -- a value past its own axis's max draws past the outer ring,
    visibly (not silently) flagging a caller's own max as too low,
    rather than hiding the overshoot. Each axis has its own
    independent max (unlike `Mark.POLAR`'s single shared radius
    domain) -- a real radar chart's whole point is comparing
    differently-scaled dimensions (e.g. "Attack" out of 100, "Crit
    Chance" out of 1.0) on one shared-looking grid.

    Each series polygon is filled (`_lighten`'d palette color, the
    same halo-tint helper `Mark.EFFECT_SCATTER` already uses, so
    overlapping series stay legible) and stroked (the full, unlightened
    palette color) -- unlike every other filled-and-stroked shape in
    this package, both drawn from the identical path, since there's no
    Theme flag to skip the fill: a radar chart with several series and
    no fill at all is unreadable overlapping-outline soup, so this
    isn't optional the way, say, `Mark.AREA`'s own stroke is.

    Legend keyed by `series_names` (only relevant with 2+ series --
    still drawn for one, the same "always draw it, `Theme.show_legend`
    is the only real toggle" convention every other legend-bearing
    mark here follows).
    """
    if len(plot._radar.indicators) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var theme = plot._theme
    var text_requests = List[_TextRequest]()

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = (
        _dynamic_legend_width(plot._radar.series_names, sc.legend_swatch_size, sc) if show_legend else 0
    )

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9

    var n = len(plot._radar.indicators)
    if theme.show_gridlines:
        _draw_radar_grid(target, cx, cy, max_radius, n, theme)

    var palette = default_categorical_palette()
    for s in range(len(plot._radar.series_values)):
        var values = plot._radar.series_values[s].copy()
        var color = palette[s % len(palette)]
        var poly = Path()
        for i in range(n):
            var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
            var frac = values[i] / plot._radar.max_values[i] if plot._radar.max_values[i] > 0.0 else 0.0
            var pt = _polar_point(cx, cy, angle, max_radius * frac)
            if i == 0:
                poly.move_to(pt.x, pt.y)
            else:
                poly.line_to(pt.x, pt.y)
        poly.close()
        target.fill_path_aa(poly, _lighten(color))
        target.stroke_path_aa(poly, color, sc.line_width)

    # Axis labels, placed just outside each spoke's own tip -- aligned
    # by which side of center the tip falls on (LEFT for the right
    # half, RIGHT for the left half, CENTER for the top/bottom-most
    # spokes) so a label never reads as overlapping its own spoke.
    for i in range(n):
        var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
        var tip = _polar_point(cx, cy, angle, max_radius + Float64(sc.label_gap))
        var c = cos(angle)
        var align = TextAlign.CENTER
        if c > 0.3:
            align = TextAlign.LEFT
        elif c < -0.3:
            align = TextAlign.RIGHT
        text_requests.append(
            _TextRequest(
                Int(tip.x), Int(tip.y), plot._radar.indicators[i], theme.text_color, sc.font_size, align, theme.font_family
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
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A radar/spider chart -- `Mark.RADAR` over `Plot.encode_radar()`'s
    own shape: `indicators` (one spoke per name, each its own
    `max_values`), and one polygon per series (`series_names` + a
    value per indicator, `series_values`). See `_render_radar`'s own
    docstring for the full reasoning."""
    var plot = Plot().mark_radar().encode_radar(
        indicators=indicators,
        max_values=max_values,
        series_names=series_names,
        series_values=series_values,
    )
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
