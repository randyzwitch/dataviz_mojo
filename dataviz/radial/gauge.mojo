from std.math import isnan, pi

from canvas.text.font_cache import FontCache
from canvas.color import Color
from canvas.vector.draw_target import DrawTarget
from canvas.text.render import TextAlign

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats

from dataviz.plot import Plot, _finished
from dataviz.core.render_result import _RenderResult
from dataviz.core.text import _Scaled, _TextRequest
from dataviz.radial.polar import _polar_point
from dataviz.core.scale import _format_fixed, _label_decimals
from dataviz.core.theme import Theme
from dataviz.core.mark import Mark, _require_mark


struct _GaugeData(Copyable, Movable):
    """A single value plus its dial range and optional custom breakpoint
    bands (empty means ECharts' 20%/80%/100% default), for `Mark.GAUGE`.
    See `encode_gauge()`. Stored on `Plot._gauge`.
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
    """Return the default low, middle, and high band endpoints."""
    return [0.2, 0.8, 1.0]


def _gauge_band_colors() -> List[Color]:
    """The three default bands' colors (green/blue/red, ECharts' default),
    used when `Plot.encode_gauge()`'s `band_colors` is left empty.
    """
    return [Color(46, 139, 87), Color(30, 144, 255), Color(220, 20, 60)]


def _render_gauge[
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
    """Render a clamped value as a needle over colored dial bands.

    The range must increase. Band endpoints and colors must have equal length,
    and endpoints must increase within `(0, 1]`.
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

    var breakpoints = (
        plot._gauge.breakpoints.copy() if len(plot._gauge.breakpoints)
        > 0 else _gauge_breakpoints()
    )
    var colors = (
        plot._gauge.band_colors.copy() if len(plot._gauge.band_colors)
        > 0 else _gauge_band_colors()
    )
    if len(breakpoints) != len(colors):
        raise Error(
            "Plot.encode_gauge(): breakpoints and band_colors must be the same"
            " length (got "
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
                "Plot.encode_gauge(): breakpoints must be strictly ascending"
                " and within (0, 1] (got "
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
    var max_radius = (
        Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    )
    var inner_radius = max_radius * plot._mark_style.gauge_band_inner_fraction

    var band_start = plot._mark_style.gauge_start_angle
    for i in range(len(breakpoints)):
        var band_end = (
            plot._mark_style.gauge_start_angle
            + plot._mark_style.gauge_sweep_angle * breakpoints[i]
        )
        target.fill_ring_sector_aa(
            cx, cy, inner_radius, max_radius, band_start, band_end, colors[i]
        )
        band_start = band_end

    var value = plot._gauge.value
    if value < plot._gauge.min_value:
        value = plot._gauge.min_value
    if value > plot._gauge.max_value:
        value = plot._gauge.max_value
    var frac = (value - plot._gauge.min_value) / (
        plot._gauge.max_value - plot._gauge.min_value
    )
    var needle_angle = (
        plot._mark_style.gauge_start_angle
        + plot._mark_style.gauge_sweep_angle * frac
    )
    var tip = _polar_point(
        cx,
        cy,
        needle_angle,
        max_radius * plot._mark_style.gauge_needle_fraction,
    )
    var tooltips_on = plot._tooltips_on(1)
    if tooltips_on:
        target.begin_annotated_group(
            _format_fixed(value, _label_decimals(value))
        )
    target.draw_line_aa(
        Int(cx),
        Int(cy),
        Int(tip.x),
        Int(tip.y),
        theme.mark_color,
        sc.line_width * 2.0,
    )
    target.fill_circle_aa(
        Int(cx), Int(cy), Int(sc.point_radius), theme.mark_color
    )
    if tooltips_on:
        target.end_annotated_group()

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
    band_inner_fraction: Float64 = 0.7,
    needle_fraction: Float64 = 0.9,
    start_angle: Float64 = 3.0 * pi / 4.0,
    sweep_angle: Float64 = 3.0 * pi / 2.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A gauge chart: a single value shown as a needle or arc against a
    min/max range, mimicking an analog dial. Reaches for the familiar
    speedometer metaphor for one KPI, though `bullet()` packs the same
    information into far less space.

    `Mark.GAUGE`: a single `value` (clamped to `[min_value, max_value]`)
    shown as a needle over a 270-degree color-banded dial (green/blue/red
    at the default 20%/80%/100% breakpoints, or `breakpoints`/
    `band_colors`' custom bands; see `Plot.encode_gauge()`). See
    `_render_gauge`.

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
        band_inner_fraction: The band ring's inner radius as a fraction of the dial
            radius; defaults to `0.7`.
        needle_fraction: The needle's length as a fraction of the dial radius;
            defaults to `0.9`.
        start_angle: Where the dial begins, in radians; defaults to `3*pi/4`.
        sweep_angle: How far the dial sweeps, in radians; defaults to `3*pi/2`
            (270 degrees).
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
        from dataviz import save

        def main() raises:
            var cpu_usage = 67.0

            var c = gauge(
                cpu_usage,
                title="Illustrative CPU Utilization (%)",
            )
            save(c, "docs/src/examples/out_gauge.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_gauge(
            band_inner_fraction=band_inner_fraction,
            needle_fraction=needle_fraction,
            start_angle=start_angle,
            sweep_angle=sweep_angle,
        )
        .encode_gauge(
            value=value,
            min_value=min_value,
            max_value=max_value,
            breakpoints=breakpoints,
            band_colors=band_colors,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def gauge(
    df: DataFrame,
    value: String,
    min_value: Float64 = 0.0,
    max_value: Float64 = 100.0,
    breakpoints: List[Float64] = List[Float64](),
    band_colors: List[Color] = List[Color](),
    band_inner_fraction: Float64 = 0.7,
    needle_fraction: Float64 = 0.9,
    start_angle: Float64 = 3.0 * pi / 4.0,
    sweep_angle: Float64 = 3.0 * pi / 2.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """Draw a gauge from one row in a named numeric DataFrame column.

    A gauge shows one reading, so the selected column must contain
    exactly one row. A missing reading cannot produce a gauge. The
    dial has no axes, so column
    names do not become axis titles.

    Args:
        df: The frame holding the reading.
        value: Name of the numeric reading column.
        min_value: See the scalar overload.
        max_value: See the scalar overload.
        breakpoints: See the scalar overload.
        band_colors: See the scalar overload.
        band_inner_fraction: See the scalar overload.
        needle_fraction: See the scalar overload.
        start_angle: See the scalar overload.
        sweep_angle: See the scalar overload.
        theme: See the scalar overload.
        width: See the scalar overload.
        height: See the scalar overload.
        title: See the scalar overload.
        subtitle: See the scalar overload.
        x_title: See the scalar overload.
        y_title: See the scalar overload.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: The column is absent, nonnumeric, missing a reading,
            or contains anything other than one row.
    """
    var readings = _frame_floats(df, value, "gauge()", theme.missing)
    if len(readings) != 1:
        raise Error(
            "gauge(): column must contain exactly one reading (got "
            + String(len(readings))
            + ")"
        )
    if isnan(readings[0]):
        raise Error("gauge(): reading is missing")
    return gauge(
        value=readings[0],
        min_value=min_value,
        max_value=max_value,
        breakpoints=breakpoints,
        band_colors=band_colors,
        band_inner_fraction=band_inner_fraction,
        needle_fraction=needle_fraction,
        start_angle=start_angle,
        sweep_angle=sweep_angle,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )


def _encode_gauge(
    mut plot: Plot,
    value: Float64,
    min_value: Float64,
    max_value: Float64,
    breakpoints: List[Float64],
    band_colors: List[Color],
) raises:
    """`Plot.encode_gauge()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(plot._mark, "encode_gauge", "mark_gauge()", Mark.GAUGE)
    plot._gauge.value = value
    plot._gauge.min_value = min_value
    plot._gauge.max_value = max_value
    plot._gauge.breakpoints = breakpoints.copy()
    plot._gauge.band_colors = band_colors.copy()
