from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.ordinal_scale import OrdinalScale
from dataviz.plot import (
    _draw_axis_spines,
    Plot,
    _RenderResult,
    _span_tooltip_label,
    _Scaled,
    _TextRequest,
    _axis_pixel,
    _axis_pixel_f,
    snap_to_pixel_edge,
    _data_extent,
    _max_label_width,
    _finished,
    _require_non_empty,
)
from dataviz.core.frame import _fitting_ticks
from dataviz.core.scale import LinearScale, _format_fixed, _label_decimals
from dataviz.core.theme import Theme


struct _HorizontalCategoricalFrame(Movable):
    """Layout for marks with a continuous x-axis and categorical y-axis."""

    var x_scale: LinearScale
    var y_scale: OrdinalScale
    var sc: _Scaled
    var text_requests: List[_TextRequest]
    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int

    def __init__(
        out self,
        var x_scale: LinearScale,
        var y_scale: OrdinalScale,
        var sc: _Scaled,
        var text_requests: List[_TextRequest],
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
    ):
        self.x_scale = x_scale^
        self.y_scale = y_scale^
        self.sc = sc^
        self.text_requests = text_requests^
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1

    def result(self) -> _RenderResult:
        """This layout as the `_RenderResult` its caller returns.

        Passes `x_scale` through with `has_x_scale=True`: on this frame
        the *x* axis is the continuous one, so `Plot.annotate_vline()`
        places a value against the same scale the data went through --
        a deadline on a Gantt's time axis, the center of a population
        pyramid. It reported neither scale until #688, which is why a
        vline on those marks raised. `y_scale` stays absent: the y axis
        here is categorical and has no numeric domain for
        `annotate_line()` to mean anything against.
        """
        return _RenderResult(
            self.text_requests.copy(),
            self.px0,
            self.py0,
            self.px1,
            self.py1,
            x_scale=self.x_scale,
            has_x_scale=True,
        )


def _draw_horizontal_categorical_axis_frame[
    T: DrawTarget
](
    mut target: T,
    categories: List[String],
    x_scale: LinearScale,
    theme: Theme,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    padding: Float64 = 0.2,
    *,
    mut cache: FontCache,
) raises -> _HorizontalCategoricalFrame:
    """Draw a continuous x-axis and top-to-bottom categorical y-axis.

    The left margin fits category labels. Vertical gridlines follow x ticks,
    and `padding` controls the categorical bands; ridgelines use zero padding.
    """
    var sc = _Scaled(theme)

    var dynamic_left_margin = (
        Int(
            _max_label_width(
                categories, sc.font_size, family=theme.font_family, cache=cache
            )
        )
        + sc.tick_length
        + sc.label_gap
        + sc.margin_buffer
    )

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom

    var out_x_scale = x_scale
    out_x_scale.range_min = Float64(plot_x0)
    out_x_scale.range_max = Float64(plot_x1)

    var y_scale = OrdinalScale(
        categories.copy(), Float64(plot_y0), Float64(plot_y1), padding
    )

    var x_ticks = _fitting_ticks(
        out_x_scale,
        Float64(plot_x1 - plot_x0),
        True,
        theme.x_tick_format,
        sc,
        theme.font_family,
        cache,
    )
    var x_labels = x_ticks.labels(theme.x_tick_format)

    if theme.show_gridlines:
        for i in range(len(x_ticks.values)):
            var px = _axis_pixel(out_x_scale, x_ticks.values[i])
            target.draw_line_aa(
                px, plot_y0, px, plot_y1, theme.gridline_color, width=sc.scale
            )

    _draw_axis_spines(
        target,
        theme,
        sc,
        plot_x0,
        plot_y0,
        plot_x1,
        plot_y1,
        x_axis_y=plot_y1,
        y_axis_x=plot_x0,
    )

    var text_requests = List[_TextRequest]()

    for i in range(len(x_ticks.values)):
        var px = _axis_pixel(out_x_scale, x_ticks.values[i])
        if theme.show_axis_bottom:
            target.draw_line_aa(
                px,
                plot_y1,
                px,
                plot_y1 + sc.tick_length,
                theme.axis_color,
                width=sc.scale,
            )
        text_requests.append(
            _TextRequest(
                px,
                plot_y1 + sc.tick_length + sc.label_gap + Int(sc.font_size),
                x_labels[i],
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for i in range(len(categories)):
        var center_py = round_to_int(y_scale.center(i))
        if theme.show_axis_left:
            target.draw_line_aa(
                plot_x0 - sc.tick_length,
                center_py,
                plot_x0,
                center_py,
                theme.axis_color,
                width=sc.scale,
            )
        text_requests.append(
            _TextRequest(
                plot_x0 - sc.tick_length - sc.label_gap,
                center_py + y_label_baseline_offset,
                categories[i],
                theme.text_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )

    return _HorizontalCategoricalFrame(
        out_x_scale,
        y_scale^,
        sc^,
        text_requests^,
        plot_x0,
        plot_y0,
        plot_x1,
        plot_y1,
    )


def _render_gantt[
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
    """Render a `Mark.GANTT` plot: `_draw_horizontal_categorical_axis_frame`'s
    horizontal categorical axis (categories along `y`, top-to-bottom;
    continuous `x` along the bottom).

    The x-domain is `_data_extent` (padded, not forced through zero) over
    every `start`/`end` value. The categorical marks split on this:
    `Mark.BAR`/`LOLLIPOP`/`WATERFALL`/`BULLET` encode magnitude from a
    baseline and force zero into view; `Mark.BOX`/`CANDLESTICK`/`GANTT`
    encode where something falls within a range, where forcing zero would
    flatten the detail.

    One floating horizontal bar per category (`fill_rect`, full row
    height, `theme.mark_color`) from `min(start[i], end[i])` to
    `max(...)`. A zero-length span (a milestone) is floored to 1px, as
    `Mark.CANDLESTICK`'s doji is.

    No dependency arrows between bars; `encode_gantt()`'s data has no
    notion of dependencies.
    """
    if len(plot._categorical.x) != len(plot._gantt.start) or len(
        plot._gantt.end
    ) != len(plot._gantt.start):
        raise Error(
            "Plot.encode_gantt(): categories, start, and end must all have"
            " the same length (got "
            + String(len(plot._categorical.x))
            + " categories, "
            + String(len(plot._gantt.start))
            + " start values, "
            + String(len(plot._gantt.end))
            + " end values)"
        )

    var theme = plot._theme
    _require_non_empty(len(plot._categorical.x), "Plot.encode_gantt()")
    var domain_data = List[Float64]()
    for v in plot._gantt.start:
        domain_data.append(v)
    for v in plot._gantt.end:
        domain_data.append(v)
    var x_scale = _data_extent(domain_data)

    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot._categorical.x,
        x_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    var row_height = frame.y_scale.bandwidth()
    for i in range(len(plot._categorical.x)):
        var row_y = frame.y_scale.band_start(i)
        var start_px = _axis_pixel_f(frame.x_scale, plot._gantt.start[i])
        var end_px = _axis_pixel_f(frame.x_scale, plot._gantt.end[i])
        # Snap the four edges, then floor the width at a pixel so a
        # zero-length task still draws a mark. The floor comes after the
        # snap: two equal edges snap to one boundary, which is exactly
        # the case it guards.
        var bx0 = snap_to_pixel_edge(min(start_px, end_px))
        var bx1 = snap_to_pixel_edge(max(start_px, end_px))
        if bx1 - bx0 < 1.0:
            bx1 = bx0 + 1.0
        var by0 = snap_to_pixel_edge(row_y)
        var by1 = snap_to_pixel_edge(row_y + row_height)
        if theme.svg_tooltips:
            target.begin_annotated_group(
                _span_tooltip_label(
                    plot._categorical.x[i],
                    plot._gantt.start[i],
                    plot._gantt.end[i],
                )
            )
        target.fill_rect(bx0, by0, bx1 - bx0, by1 - by0, theme.mark_color)
        if theme.svg_tooltips:
            target.end_annotated_group()
        if theme.show_data_labels:
            var span = abs(plot._gantt.end[i] - plot._gantt.start[i])
            frame.text_requests.append(
                _TextRequest(
                    round_to_int(bx1) + frame.sc.label_gap,
                    round_to_int((by0 + by1) / 2.0 + frame.sc.font_size * 0.35),
                    _format_fixed(span, _label_decimals(span)),
                    theme.text_color,
                    frame.sc.font_size,
                    TextAlign.LEFT,
                    theme.font_family,
                )
            )

    return frame.result()


def gantt[
    dtype: DType
](
    categories: List[String],
    start: List[Scalar[dtype]],
    end: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A gantt/span chart, the project-scheduling format popularized by
    Henry Gantt in the 1910s: one horizontal bar per category spanning
    its start and end, for visualizing overlapping durations such as a
    project's tasks or a schedule's bookings.

    `Mark.GANTT`: one horizontal bar per category from `start[i]` to
    `end[i]`.

    Args:
        categories: One horizontal bar per entry, top to bottom.
        start: Each bar's starting value.
        end: Each bar's ending value.
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
        from dataviz import gantt
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            # Illustrative six-week release plan with deliberately overlapping
            # product, engineering, documentation, and rollout workstreams.
            var tasks: List[String] = [
                "Discovery", "UX design", "API implementation", "UI build",
                "Integration testing", "Documentation", "Pilot rollout",
                "General availability",
            ]
            var start: List[Int] = [0, 3, 8, 10, 22, 17, 30, 39]
            var end: List[Int] = [6, 12, 25, 27, 34, 32, 38, 42]

            var c = gantt(
                tasks,
                start,
                end,
                title="Illustrative Product Release Schedule",
                x_title="Day since project start",
                y_title="Workstream",
            )
            save(c, "docs/src/examples/out_gantt.svg")
        ```
    """
    var start_f = _materialize_scalar_list(start)
    var end_f = _materialize_scalar_list(end)
    var plot = (
        Plot()
        .mark_gantt()
        .encode_gantt(categories=categories, start=start_f, end=end_f)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
