from canvas.geometry import _round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _axis_pixel,
    _data_extent,
    _max_label_width,
    _finished,
    _require_non_empty,
)
from dataviz.scale import LinearScale
from dataviz.theme import Theme


struct _HorizontalCategoricalFrame(Movable):
    """`_draw_horizontal_categorical_axis_frame`'s finished layout: the
    mirror image of `_CategoricalFrame`, with `x_scale` the continuous
    `LinearScale` and `y_scale` the categorical `OrdinalScale`. Shared by
    every mark whose categories run along the y-axis (`Mark.GANTT`,
    `POPULATION_PYRAMID`, `RIDGELINE`, and the `horizontal=True` variants
    of `Mark.BAR`/`BOX`/`VIOLIN`/`BEESWARM`/`LOLLIPOP`).
    `px0`/`py0`/`px1`/`py1` are the inner plot rect, as in
    `_CategoricalFrame`.
    """

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
        """This frame as the `_RenderResult` the caller returns; mirrors
        `_CategoricalFrame.result` (plot.mojo), including copying
        `text_requests` rather than moving it.
        """
        return _RenderResult(
            self.text_requests.copy(), self.px0, self.py0, self.px1, self.py1
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
) raises -> _HorizontalCategoricalFrame:
    """`_draw_categorical_axis_frame`'s mirror image: categories run along
    an `OrdinalScale` y-axis (index 0 at the top) and the continuous
    `x_scale` runs left-to-right along the bottom. Its own function
    rather than an orientation flag on `_draw_categorical_axis_frame`,
    which would need a branch through nearly every line (which scale is
    which type, which axis reverses, which margin grows).

    The dynamic left margin grows to fit the category names themselves
    (`_max_label_width(categories, ...)`, the raw strings, since an
    `OrdinalScale`'s domain is the label text) rather than formatted tick
    values.

    Category index 0 lands at the top: `OrdinalScale(categories, plot_y0,
    plot_y1)` with `plot_y0 < plot_y1`, not reversed, so a schedule lists
    its first task first.

    No per-row gridlines (the rows already separate categories); vertical
    gridlines at each of `x_scale`'s ticks instead.

    `padding` (default 0.2) is forwarded to the `OrdinalScale`.
    `Mark.RIDGELINE` passes `padding=0.0` so each row's baseline lands
    exactly on the next row's top edge; with any gap, a sliver of
    background shows between rows and reads as a notch.
    """
    var sc = _Scaled(theme)

    var dynamic_left_margin = (
        Int(_max_label_width(categories, sc.font_size))
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

    var x_ticks = out_x_scale.ticks()
    var x_labels = x_ticks.labels(theme.x_tick_format)

    if theme.show_gridlines:
        for i in range(len(x_ticks.values)):
            var px = _axis_pixel(out_x_scale, x_ticks.values[i])
            target.draw_line_aa(
                px, plot_y0, px, plot_y1, theme.gridline_color, width=sc.scale
            )

    target.draw_line_aa(
        plot_x0, plot_y1, plot_x1, plot_y1, theme.axis_color, width=sc.scale
    )
    target.draw_line_aa(
        plot_x0, plot_y0, plot_x0, plot_y1, theme.axis_color, width=sc.scale
    )

    var text_requests = List[_TextRequest]()

    for i in range(len(x_ticks.values)):
        var px = _axis_pixel(out_x_scale, x_ticks.values[i])
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
        var center_py = _round_to_int(y_scale.center(i))
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
    mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int
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
    if len(plot.x_categories) != len(plot._gantt.start) or len(
        plot._gantt.end
    ) != len(plot._gantt.start):
        raise Error(
            "Plot.encode_gantt(): categories, start, and end must all have"
            " the same length (got "
            + String(len(plot.x_categories))
            + " categories, "
            + String(len(plot._gantt.start))
            + " start values, "
            + String(len(plot._gantt.end))
            + " end values)"
        )

    var theme = plot._theme
    _require_non_empty(len(plot.x_categories), "Plot.encode_gantt()")
    var domain_data = List[Float64]()
    for v in plot._gantt.start:
        domain_data.append(v)
    for v in plot._gantt.end:
        domain_data.append(v)
    var x_scale = _data_extent(domain_data)

    var frame = _draw_horizontal_categorical_axis_frame(
        target, plot.x_categories, x_scale, theme, ox0, oy0, ox1, oy1
    )

    var row_height = _round_to_int(frame.y_scale.bandwidth())
    for i in range(len(plot.x_categories)):
        var row_y = _round_to_int(frame.y_scale.band_start(i))
        var start_px = _axis_pixel(frame.x_scale, plot._gantt.start[i])
        var end_px = _axis_pixel(frame.x_scale, plot._gantt.end[i])
        var bar_x = min(start_px, end_px)
        var bar_width = max(1, max(start_px, end_px) - min(start_px, end_px))
        target.fill_rect(bar_x, row_y, bar_width, row_height, theme.mark_color)

    return frame.result()


def gantt(
    categories: List[String],
    start: List[Float64],
    end: List[Float64],
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
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var tasks: List[String] = ["Design", "Development", "Testing", "Documentation", "Launch"]
            var start: List[Int] = [0, 5, 20, 15, 28]
            var end: List[Int] = [8, 25, 28, 27, 30]

            var c = gantt(tasks, start, end)
            save(c, "docs/src/examples/out_gantt.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_gantt()
        .encode_gantt(categories=categories, start=start, end=end)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


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
    """`gantt()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). `start`/`end` share one dtype. Delegates
    to the concrete overload above.
    """
    return gantt(
        categories,
        _materialize_scalar_list(start),
        _materialize_scalar_list(end),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
