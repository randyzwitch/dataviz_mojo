from std.math import pi

from canvas_mojo.color import Color
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas
from canvas_mojo.text.render import TextAlign

from dataviz.mark import Mark
from dataviz.plot import Plot, _RenderResult, _Scaled, _TextRequest, _finished
from dataviz.polar import _polar_point
from dataviz.scale import _format_fixed
from dataviz.theme import Theme


struct _GaugeData(Movable):
    """
    Mark.GAUGE only -- a single value plus its dial range, plus the
    optional custom breakpoint bands (empty means "use ECharts' 20%/80%/100% default", the same empty-list-is-a-sentinel convention
    `encode()`'s `color`/`size` channels already use). See
    encode_gauge()'s docstring.

    Grouped onto `Plot._gauge` -- see `Plot`'s docstring.
    """

    var value: Float64
    var min_value: Float64
    var max_value: Float64
    var breakpoints: List[Float64]
    var band_colors: List[Color]

    def __init__(out self):
        self.value = 0.0
        self.min_value = 0.0
        self.max_value = 0.0
        self.breakpoints = List[Float64]()
        self.band_colors = List[Color]()


def _gauge_breakpoints() -> List[Float64]:
    """ECharts' default breakpoints (a gauge's value range split
    into low/mid/high bands at 20%/80%/100%) -- the fallback `_render_
    gauge` draws when `Plot.encode_gauge()`'s `breakpoints` is left
    at its default empty list (see that method's docstring for the
    "empty means use this default" sentinel convention, and the render-
    time validation once a caller *does* supply their own). A plain
    function, not a `Theme` field -- the same `List`-breaks-
    `ImplicitlyCopyable` reasoning `default_categorical_palette()`
    gives for keeping a fixed default list out of `Theme` itself."""
    return [0.2, 0.8, 1.0]


def _gauge_band_colors() -> List[Color]:
    """The three breakpoint bands' colors -- green/blue/red,
    ECharts' default, drawn whenever `Plot.encode_gauge()`'s `band_colors` is left at its default empty list. See `_gauge_
    breakpoints()`'s docstring for why this is a plain function,
    not a `Theme` field."""
    return [Color(46, 139, 87), Color(30, 144, 255), Color(220, 20, 60)]


def _render_gauge[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.GAUGE` plot: `encode_gauge()`'s single
    `value` (clamped to `[min_value, max_value]` before drawing -- a
    real, visible "pinned at the end of the dial" reading for an out-
    of-range value, not an error the way most other value validation
    in this package is; a gauge's whole point is a live reading that
    can legitimately go out of its expected range) as a needle
    (`draw_line_aa`, `theme.mark_color`) over `breakpoints`/`band_
    colors`' colored ring-sector bands (`fill_ring_sector_aa`, the
    same primitive `Mark.ARC`'s donut mode uses -- falling back to
    `_gauge_breakpoints()`/`_gauge_band_colors()`'s fixed 20%/80%/
    100% green/blue/red default when `encode_gauge()`'s `breakpoints`/
    `band_colors` were left empty, see that method's docstring),
    plus a small pivot circle at the center and the value itself as a
    centered text label below it.

    `min_value` must be strictly less than `max_value` (checked at
    render() time) -- a zero-or-negative span has no dial to sweep.
    A non-default `breakpoints`/`band_colors` pair must be the same
    length, non-empty, strictly ascending, and stay within `(0, 1]` --
    each entry is a fraction of the full dial sweep, so anything
    outside that range (or a non-ascending order, which would draw a
    band backwards) has no dial position to mean. No axis frame, no
    legend -- a gauge has exactly one value and no categories to key
    either by.
    """
    var theme = plot._theme
    if plot._gauge.min_value >= plot._gauge.max_value:
        raise Error(
            "Plot.encode_gauge(): min_value must be less than max_value (got "
            + String(plot._gauge.min_value)
            + " and "
            + String(plot._gauge.max_value)
            + ")"
        )

    var breakpoints = plot._gauge.breakpoints.copy() if len(plot._gauge.breakpoints) > 0 else _gauge_breakpoints()
    var colors = plot._gauge.band_colors.copy() if len(plot._gauge.band_colors) > 0 else _gauge_band_colors()
    if len(breakpoints) != len(colors):
        raise Error(
            "Plot.encode_gauge(): breakpoints and band_colors must be the same length (got "
            + String(len(breakpoints))
            + " and "
            + String(len(colors))
            + ")"
        )
    var prev = 0.0
    for i in range(len(breakpoints)):
        var b = breakpoints[i]
        if b <= prev or b > 1.0:
            raise Error(
                "Plot.encode_gauge(): breakpoints must be strictly ascending and within (0, 1] (got "
                + String(b)
                + " after "
                + String(prev)
                + ")"
            )
        prev = b

    var text_requests = List[_TextRequest]()
    var sc = _Scaled(theme)
    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    var inner_radius = max_radius * theme.gauge_band_inner_fraction

    var band_start = theme.gauge_start_angle
    for i in range(len(breakpoints)):
        var band_end = theme.gauge_start_angle + theme.gauge_sweep_angle * breakpoints[i]
        target.fill_ring_sector_aa(cx, cy, inner_radius, max_radius, band_start, band_end, colors[i])
        band_start = band_end

    var value = plot._gauge.value
    if value < plot._gauge.min_value:
        value = plot._gauge.min_value
    if value > plot._gauge.max_value:
        value = plot._gauge.max_value
    var frac = (value - plot._gauge.min_value) / (plot._gauge.max_value - plot._gauge.min_value)
    var needle_angle = theme.gauge_start_angle + theme.gauge_sweep_angle * frac
    var tip = _polar_point(cx, cy, needle_angle, max_radius * theme.gauge_needle_fraction)
    target.draw_line_aa(Int(cx), Int(cy), Int(tip.x), Int(tip.y), theme.mark_color, sc.line_width * 2.0)
    target.fill_circle_aa(Int(cx), Int(cy), Int(sc.point_radius), theme.mark_color)

    text_requests.append(
        _TextRequest(
            Int(cx),
            Int(cy) + Int(inner_radius * 0.5),
            _format_fixed(plot._gauge.value, 1),
            theme.text_color,
            sc.title_font_size,
            TextAlign.CENTER,
            theme.font_family,
        )
    )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def gauge(
    value: Float64,
    min_value: Float64 = 0.0,
    max_value: Float64 = 100.0,
    breakpoints: List[Float64] = List[Float64](),
    band_colors: List[Color] = List[Color](),
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A gauge chart -- `Mark.GAUGE`, a single `value` (clamped to
    `[min_value, max_value]`) shown as a needle over a 270-degree
    color-banded dial (green/blue/red at the default 20%/80%/100%
    breakpoints, or `breakpoints`/`band_colors`' custom bands --
    see `Plot.encode_gauge()`'s docstring for the sentinel-empty-
    means-default convention and validation). See `_render_gauge`'s docstring for the full reasoning.

    Args:
        value: The reading to show, clamped (not rejected) to
            `[min_value, max_value]` -- an out-of-range value pins
            visibly at the end of the dial.
        min_value: The dial's low end; defaults to `0.0`.
        max_value: The dial's high end; defaults to `100.0`, giving a
            plain percentage-style gauge with the default `value`.
        breakpoints: Ascending fractions of the full `[min_value,
            max_value]` span (e.g. `[0.5, 1.0]` for a low/high split);
            left empty (the default), reproduces ECharts' fixed
            20%/80%/100% bands unchanged.
        band_colors: One color per `breakpoints` band, same length;
            left empty (the default), reproduces ECharts' fixed
            green/blue/red bands unchanged.
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
        from dataviz import gauge
        from dataviz.plot import save

        def main() raises:
            var cpu_usage = 67.0

            var c = gauge(cpu_usage)
            save(c, "docs/src/examples/out_gauge.svg")
        ```
    """
    var plot = Plot().mark_gauge().encode_gauge(
        value=value, min_value=min_value, max_value=max_value, breakpoints=breakpoints, band_colors=band_colors
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
