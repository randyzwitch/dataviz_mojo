from canvas.text.font_cache import FontCache
from canvas.color import Color
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list

from canvas.text.render import TextAlign
from dataviz.ordinal_scale import OrdinalScale
from dataviz.scale import LinearScale, _format_tick, _label_decimals
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Orientation,
    _Scaled,
    _tooltip_label,
    _TextRequest,
    _axis_pixel_f,
    _draw_categorical_axis_frame,
    _pull_off_axis_line_f,
    _finished,
    _zero_baseline_y_extent,
    _validate_categorical_encoding,
)
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.theme import Theme


def _bar_fill_color(theme: Theme, value: Float64) -> Color:
    """The fill color `_draw_bar_rects` picks per bar:
    `Theme.mark_color_negative` when `Theme.color_by_sign` is on and the
    value is negative, `Theme.mark_color` otherwise.
    """
    return theme.mark_color_negative if (
        theme.color_by_sign and value < 0.0
    ) else theme.mark_color


def _bar_y_domain_data(plot: Plot) -> List[Float64]:
    """`plot.y_data`, or every error-bar whisker endpoint when `y_err`
    (or `y_err_lower`/`y_err_upper`) is set (#216), so the y-domain spans
    everything `_draw_bar_rects` actually draws -- the same
    `y_domain_data` pattern `_render_generic` uses for `POINT`/`LINE`/
    `EFFECT_SCATTER`.
    """
    var domain_data = List[Float64]()
    if len(plot.y_err_data) > 0:
        for i in range(len(plot.y_data)):
            domain_data.append(plot.y_data[i] - plot.y_err_data[i])
            domain_data.append(plot.y_data[i] + plot.y_err_data[i])
    elif len(plot.y_err_lower_data) > 0:
        for i in range(len(plot.y_data)):
            domain_data.append(plot.y_data[i] - plot.y_err_lower_data[i])
            domain_data.append(plot.y_data[i] + plot.y_err_upper_data[i])
    else:
        for v in plot.y_data:
            domain_data.append(v)
    return domain_data^


def _draw_bar_rects[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    band_scale: OrdinalScale,
    value_scale: LinearScale,
    baseline_edge: Int,
    orient: _Orientation,
    mut text_requests: List[_TextRequest],
) raises:
    """Draw one `Mark.BAR` plot's rectangles (and, with
    `Theme.show_data_labels`, each one's value label) into an
    already-laid-out categorical axis frame. Written once for both
    orientations; `_Orientation` carries the two differences (which way a
    rect is emitted, where its label sits).

    Factored out of `_render_bar` so `render_layers()`'s bar-combo path
    (`_render_bar_combo_layers`, plot.mojo) can draw a `Mark.BAR` layer
    against a frame it built, the same split `_draw_point_layer`/
    `_draw_line_layer`/`_draw_area_layer` use. That combo path is
    vertical-only and passes `_Orientation(False)`.

    `band_scale`/`value_scale` come from the caller's frame, and
    `baseline_edge` is that frame's axis line (`py1` vertically, `px0`
    horizontally) for `_pull_off_axis_line`. Color-by-sign and label
    sizing read `plot._theme` through this function's own
    `_Scaled(theme)`, so a layered bar follows its own `Theme.scale`.

    `Plot.encode_categorical()`'s `y_err`/`y_err_lower`/`y_err_upper`
    (#216), when set, draws a capped whisker at each bar's value edge
    first, in that bar's own resolved color, the same "whisker first,
    mark on top" order `_draw_point_layer` uses.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var baseline = _axis_pixel_f(value_scale, 0.0)
    # bandwidth() doesn't depend on the category index, so it's hoisted out
    # of the loop.
    var band_size = band_scale.bandwidth()
    var has_y_err = len(plot.y_err_data) > 0 or len(plot.y_err_lower_data) > 0
    var cap_half = sc.error_bar_cap_width
    for i in range(len(plot.x_categories)):
        var band_pos = band_scale.band_start(i)
        var value = plot.y_data[i]
        var extent = _pull_off_axis_line_f(
            baseline, _axis_pixel_f(value_scale, value), Float64(baseline_edge)
        )
        var color = _bar_fill_color(theme, value)
        if theme.svg_tooltips:
            target.begin_annotated_group(
                _tooltip_label(plot.x_categories[i], value)
            )
        if has_y_err:
            var lo: Float64
            var hi: Float64
            if len(plot.y_err_data) > 0:
                var err = plot.y_err_data[i]
                lo = value - err
                hi = value + err
            else:
                lo = value - plot.y_err_lower_data[i]
                hi = value + plot.y_err_upper_data[i]
            var center_i = band_scale.center(i)
            var py_hi = _axis_pixel_f(value_scale, hi)
            var py_lo = _axis_pixel_f(value_scale, lo)
            orient.value_line(target, py_hi, py_lo, center_i, color, sc.scale)
            orient.band_line(
                target,
                py_hi,
                center_i - cap_half,
                center_i + cap_half,
                color,
                sc.scale,
            )
            orient.band_line(
                target,
                py_lo,
                center_i - cap_half,
                center_i + cap_half,
                color,
                sc.scale,
            )
        orient.fill_band_rect(target, extent, band_pos, band_size, color)
        if theme.svg_tooltips:
            target.end_annotated_group()
        if theme.show_data_labels:
            var at = orient.outside_band_label(
                extent,
                band_pos,
                band_size,
                value < 0.0,
                sc.label_gap,
                sc.font_size,
            )
            text_requests.append(
                _TextRequest(
                    at.x,
                    at.y,
                    _format_tick(
                        value,
                        _label_decimals(value),
                        theme.x_tick_format if orient.horizontal else theme.y_tick_format,
                    ),
                    theme.text_color,
                    sc.font_size,
                    at.align,
                    theme.font_family,
                )
            )


def _render_bar[
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
    """Render a `Mark.BAR` plot: a categorical x-axis (`OrdinalScale`, one
    evenly spaced band per category) and a continuous y-axis whose domain
    always includes a zero baseline (`_zero_baseline_y_extent`, not the
    continuous marks' `_data_extent`). Generic over `T: DrawTarget`,
    returning axis/tick labels as `_TextRequest`s rather than drawing
    them (see `_render_generic`).

    `ox0`/`oy0`/`ox1`/`oy1` are `render()`'s already-resolved outer
    bounds (never the -1 sentinel); this function lays out relative to
    that rectangle, whether the whole target or one facet cell.

    The axis frame is `_draw_categorical_axis_frame`'s job, shared with
    `Mark.LOLLIPOP`/`WATERFALL`/`BOX`; the rects are `_draw_bar_rects`,
    shared with `render_layers()`'s bar-combo path.
    `Theme.show_data_labels` draws each bar's value above it (below it
    for a negative value). No x-gridlines: the bars already separate
    categories.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    # y-domain computed before the frame's dynamic left margin is
    # finalized; see _draw_categorical_axis_frame for why it takes y_scale
    # as an input.
    var y_scale = _zero_baseline_y_extent(_bar_y_domain_data(plot))
    var frame = _draw_categorical_axis_frame(
        target,
        plot.x_categories,
        y_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    _draw_bar_rects(
        target,
        plot,
        frame.x_scale,
        frame.y_scale,
        frame.py1,
        _Orientation(False),
        frame.text_requests,
    )

    # `frame.result()` copies `text_requests` rather than moving it: Mojo
    # rejects moving a single field out of `frame` ("field destroyed out of
    # the middle of a value").
    return frame.result()


def _render_horizontal_bar[
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
    """`_render_bar`'s mirror image for `Plot.mark_bar(horizontal=True)`
    (#121): a categorical y-axis (`OrdinalScale`, top to bottom) and a
    continuous x-axis whose domain includes a zero baseline
    (`_zero_baseline_y_extent`, axis-agnostic despite the name).

    A separate function rather than an orientation flag on `_render_bar`,
    for the same reason `_draw_horizontal_categorical_axis_frame`
    (gantt.mojo) stays separate from `_draw_categorical_axis_frame`: a
    bidirectional frame would need a branch on nearly every line (which
    scale is which type, which axis reverses, which margin grows). The
    rect drawing itself is shared through `_draw_bar_rects` and
    `_Orientation(True)`. No y-gridlines, mirroring `_render_bar`'s no
    x-gridlines.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    var x_scale = _zero_baseline_y_extent(_bar_y_domain_data(plot))
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot.x_categories,
        x_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    _draw_bar_rects(
        target,
        plot,
        frame.y_scale,
        frame.x_scale,
        frame.px0,
        _Orientation(True),
        frame.text_requests,
    )

    return frame.result()


def bar(
    categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """A bar chart, the standard choice for comparing a value across
    discrete categories: one rectangle per category, its length
    proportional to the value, with negative values extending below the
    zero baseline.

    `Mark.BAR` over a categorical `x` and continuous `y` (see
    `Plot.encode_categorical()`); one bar per entry, with negative values
    extending below the zero baseline.

    Args:
        categories: One bar per entry, in the given order.
        values: Each bar's height; negative values extend below the
            zero baseline automatically.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.
        horizontal: Draw categories running top-to-bottom with each
            bar extending left-to-right instead of the default
            vertical layout -- see `Plot.mark_bar()`'s own docstring
            (#121).

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import bar
        from dataviz.plot import save
        from dataviz.colors import SEAGREEN
        from dataviz.theme import Theme

        def main() raises:
            var categories: List[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            var values: List[Int] = [12, 19, 8, 15, 22, -4, 6]

            var c = bar(categories, values, theme=Theme(mark_color=SEAGREEN))
            save(c, "docs/src/examples/out_bar.svg")
        ```

    Example (Diverging bars (color_by_sign)):
        ```mojo
        from dataviz import bar
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
            var net_change: List[Float64] = [15.0, -8.0, 22.0, -3.0, 10.0, -12.0]

            var c_diverging = bar(quarters, net_change, theme=Theme(color_by_sign=True))
            save(c_diverging, "docs/src/examples/out_bar_diverging.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_bar(horizontal=horizontal)
        .encode_categorical(x=categories, y=values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def bar[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """`bar()` generalized over numeric element type (`List[Int]`,
    `List[Float32]`, ...); see `scatter()`'s `DType` overload (plot.mojo).
    Delegates to the concrete overload above.
    """
    return bar(
        categories,
        _materialize_scalar_list(values),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
        horizontal=horizontal,
    )
