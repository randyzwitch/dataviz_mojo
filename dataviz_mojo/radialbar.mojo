from std.math import pi

from canvas_mojo.color import Color
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas

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
    _rendered,
    _validate_categorical_encoding,
    _require_non_negative,
    _require_some_positive,
)
from dataviz_mojo.theme import Theme

# A light neutral gray for each ring's own full-circle "track" -- drawn
# first, underneath the value arc, the same "unfilled background the
# filled portion reads against" role a real progress bar's own track
# plays. Fixed here rather than a `Theme` field, the same "not worth a
# knob until something concrete needs one" reasoning every other
# module-level layout constant in this package already follows.
comptime _RADIALBAR_TRACK_COLOR = Color(230, 230, 230)

# The radial gap between adjacent rings, as a fraction of each ring's
# own equal-thickness slot -- split evenly off both the inner and outer
# edge, the same "carve a gap out of an equal-width slot" convention
# `_POLAR_BAR_PADDING` already uses, just along the radius instead of
# the angle: `Mark.POLAR_BAR`'s bars are separated *angularly* because
# they share one radius; `RADIALBAR`'s rings are separated *radially*
# because they share one full 2*pi sweep instead.
comptime _RADIALBAR_RING_GAP_FRACTION = 0.25


def _render_radialbar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.RADIALBAR` plot: one concentric ring per category
    (`encode_categorical`'s own `x`/`y`, the identical shape `Mark.ARC`/
    `Mark.POLAR_BAR`/`Mark.NIGHTINGALE` already share -- a radial-bar
    chart is the same category+value data as a polar bar chart, just
    read as concentric progress rings instead of bars radiating from
    the center), each ring's own value drawn as a clockwise-from-12-
    o'clock arc (`_polar_point`'s own convention, reused by every polar
    mark in this package) over a full light-gray "track" circle, swept
    to `value / max(values)` of the way around -- the same always-
    linear-against-the-data's-own-max normalization `Mark.POLAR_BAR`
    already uses (no per-category goal; every ring answers "how does
    this compare to the largest value here", not "how close is this to
    its own separate target").

    The first category's own ring is drawn *outermost* (largest,
    most prominent), each later category nesting one ring further in
    -- the "primary metric outermost" convention real multi-ring
    progress widgets (Apple Watch's own activity rings, GitHub's own
    contribution-ring widgets) already use. This is the opposite
    ordering from `Mark.SUNBURST`'s own innermost-first rings, which
    encode hierarchy *depth* (a real structural property), not display
    prominence -- there's no hierarchy here for depth to mean anything.

    Same validation as `POLAR_BAR`: every value non-negative, at least
    one strictly positive (otherwise there's no max to normalize
    against).
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var text_requests = List[_TextRequest]()

    _require_non_negative(plot.y_data, "Mark.RADIALBAR")
    var max_v = _require_some_positive(plot.y_data, "Mark.RADIALBAR")

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _dynamic_legend_width(plot.x_categories, sc.legend_swatch_size, sc) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9

    var palette = default_categorical_palette()
    var n = len(plot.x_categories)
    var ring_slot = max_radius / Float64(n)
    var gap = ring_slot * _RADIALBAR_RING_GAP_FRACTION
    var start_angle = -pi / 2.0
    for i in range(n):
        var outer = max_radius - ring_slot * Float64(i) - gap / 2.0
        var inner = max_radius - ring_slot * Float64(i + 1) + gap / 2.0
        var color = palette[i % len(palette)]
        target.fill_ring_sector_aa(cx, cy, inner, outer, start_angle, start_angle + 2.0 * pi, _RADIALBAR_TRACK_COLOR)
        var frac = plot.y_data[i] / max_v
        if frac > 0.0:
            target.fill_ring_sector_aa(cx, cy, inner, outer, start_angle, start_angle + 2.0 * pi * frac, color)

    if show_legend:
        _draw_legend(
            target, text_requests, plot.x_categories, palette, plot_x1 + sc.margin_right, plot_y0, theme
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def radialbar(
    categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A radial (multi-ring) progress chart -- `Mark.RADIALBAR` over
    the same categorical `x` + continuous `y` shape `bar()`/`pie()`/
    `polarbar()` take (every value must be non-negative, and at least
    one positive). Each category becomes its own concentric ring, swept
    clockwise from 12 o'clock to `value / max(values)` of the way
    around a light-gray track -- the first category's own ring drawn
    outermost. See `_render_radialbar`'s own docstring for the full
    reasoning, including how this differs from `polarbar()`'s radiating
    bars."""
    var plot = Plot().mark_radialbar().encode_categorical(x=categories, y=values)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
