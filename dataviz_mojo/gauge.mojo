from std.math import pi

from canvas_mojo.color import Color
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas
from canvas_mojo.text.render import TextAlign

from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import Plot, _RenderResult, _Scaled, _TextRequest, _rendered
from dataviz_mojo.polar import _polar_point
from dataviz_mojo.scale import _format_fixed
from dataviz_mojo.theme import Theme

# The dial's own sweep: a 270-degree (3*pi/2) arc starting at 135
# degrees (bottom-left, past `_polar_point`'s own east-is-zero/
# clockwise convention -- see that function's own docstring) and
# ending at 45 degrees (bottom-right), leaving a 90-degree gap at the
# very bottom -- the standard gauge-chart shape (ECharts' own default
# startAngle=225/endAngle=-45, the identical sweep expressed the other
# rotation direction). Fixed constants, not `Theme` fields, matching
# `Mark.POLAR`/`RADAR`'s own module-level layout constants -- not
# worth a knob until something concrete needs one.
comptime _GAUGE_START = 3.0 * pi / 4.0
comptime _GAUGE_SWEEP = 3.0 * pi / 2.0

def _gauge_breakpoints() -> List[Float64]:
    """ECharts' own default breakpoints (a gauge's value range split
    into low/mid/high bands at 20%/80%/100%) -- fixed here rather than
    exposed through `encode_gauge()`'s own parameters, a real v1 scope
    choice (the same kind `Mark.CHORD`'s straight-rim ribbons or `Mark.
    RADAR`'s fixed grid-ring count already are): worth making
    configurable if a concrete caller needs different bands, not built
    as a knob speculatively now. A plain function, not a `Theme` field
    -- the same `List`-breaks-`ImplicitlyCopyable` reasoning `default_
    categorical_palette()`'s own docstring already gives for keeping a
    fixed default list out of `Theme` itself."""
    return [0.2, 0.8, 1.0]


def _gauge_band_colors() -> List[Color]:
    """The three breakpoint bands' own colors -- green/blue/red,
    ECharts' own default. See `_gauge_breakpoints()`'s own docstring
    for why this is a plain function, not a `Theme` field."""
    return [Color(46, 139, 87), Color(30, 144, 255), Color(220, 20, 60)]


# The color band ring's own inner radius, and the needle's own length,
# each a fraction of the dial's max radius -- the needle deliberately
# shorter than the band ring's own outer edge (`max_radius`) so its
# own tip doesn't visually collide with the band it's pointing into.
comptime _GAUGE_BAND_INNER_FRACTION = 0.7
comptime _GAUGE_NEEDLE_FRACTION = 0.9


def _render_gauge[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.GAUGE` plot: `encode_gauge()`'s own single
    `value` (clamped to `[min_value, max_value]` before drawing -- a
    real, visible "pinned at the end of the dial" reading for an out-
    of-range value, not an error the way most other value validation
    in this package is; a gauge's whole point is a live reading that
    can legitimately go out of its expected range) as a needle
    (`draw_line_aa`, `theme.mark_color`) over `_GAUGE_BREAKPOINTS`'
    own three colored ring-sector bands (`fill_ring_sector_aa`, the
    same primitive `Mark.ARC`'s own donut mode uses), plus a small
    pivot circle at the center and the value itself as a centered
    text label below it.

    `min_value` must be strictly less than `max_value` (checked at
    render() time) -- a zero-or-negative span has no dial to sweep.
    No axis frame, no legend -- a gauge has exactly one value and no
    categories to key either by.
    """
    var theme = plot._theme
    if plot._gauge_min >= plot._gauge_max:
        raise Error(
            "Plot.encode_gauge(): min_value must be less than max_value (got "
            + String(plot._gauge_min)
            + " and "
            + String(plot._gauge_max)
            + ")"
        )

    var text_requests = List[_TextRequest]()
    var sc = _Scaled(theme)
    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    var inner_radius = max_radius * _GAUGE_BAND_INNER_FRACTION

    var band_start = _GAUGE_START
    var breakpoints = _gauge_breakpoints()
    var colors = _gauge_band_colors()
    for i in range(3):
        var band_end = _GAUGE_START + _GAUGE_SWEEP * breakpoints[i]
        target.fill_ring_sector_aa(cx, cy, inner_radius, max_radius, band_start, band_end, colors[i])
        band_start = band_end

    var value = plot._gauge_value
    if value < plot._gauge_min:
        value = plot._gauge_min
    if value > plot._gauge_max:
        value = plot._gauge_max
    var frac = (value - plot._gauge_min) / (plot._gauge_max - plot._gauge_min)
    var needle_angle = _GAUGE_START + _GAUGE_SWEEP * frac
    var tip = _polar_point(cx, cy, needle_angle, max_radius * _GAUGE_NEEDLE_FRACTION)
    target.draw_line_aa(Int(cx), Int(cy), Int(tip.x), Int(tip.y), theme.mark_color, sc.line_width * 2.0)
    target.fill_circle_aa(Int(cx), Int(cy), Int(sc.point_radius), theme.mark_color)

    text_requests.append(
        _TextRequest(
            Int(cx),
            Int(cy) + Int(inner_radius * 0.5),
            _format_fixed(plot._gauge_value, 1),
            theme.text_color,
            sc.title_font_size,
            TextAlign.CENTER,
        )
    )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def gauge(
    value: Float64,
    min_value: Float64 = 0.0,
    max_value: Float64 = 100.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A gauge chart -- `Mark.GAUGE`, a single `value` (clamped to
    `[min_value, max_value]`) shown as a needle over a 270-degree
    color-banded dial (green/blue/red at the default 20%/80%/100%
    breakpoints). See `_render_gauge`'s own docstring for the full
    reasoning."""
    var plot = Plot().mark_gauge().encode_gauge(value=value, min_value=min_value, max_value=max_value)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
