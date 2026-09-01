from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz.array_like import _materialize_scalar_list

from canvas_mojo.text.render import TextAlign
from dataviz.mark import Mark
from dataviz.ordinal_scale import OrdinalScale
from dataviz.scale import LinearScale, _format_fixed, _label_decimals
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _empty_result,
    _pull_off_axis_line,
    _finished,
    _zero_baseline_y_extent,
    _validate_categorical_encoding,
)
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.theme import Theme


def _draw_bar_rects[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    x_scale: OrdinalScale,
    y_scale: LinearScale,
    py1: Int,
    mut text_requests: List[_TextRequest],
) raises:
    """Draw one `Mark.BAR` plot's rectangles (and, when `Theme.show_
    data_labels` is set, each one's value label) into an already-laid-
    out categorical axis frame -- the exact loop `_render_bar` runs
    against its own freshly-built frame, factored out so `render_
    layers()`'s bar-combo path (`_render_bar_combo_layers`, plot.mojo)
    can draw a `Mark.BAR` layer against a frame *it* built (shared
    across every layer), instead of `_render_bar` building its own
    standalone one -- the same "share the drawing primitive, not just
    the layout" split `_draw_point_layer`/`_draw_line_layer`/`_draw_
    area_layer` (plot.mojo) already use for the continuous marks
    `render()` and `render_layers()` both draw.

    `py1` is the frame's own bottom pixel row (`_pull_off_axis_line`'s
    "don't paint over the axis line's antialiasing" check needs it) --
    passed separately rather than bundled with `x_scale`/`y_scale`
    since neither scale type carries a plot rect's edges itself.
    `text_requests` is the caller's own list to append any labels
    into (`frame.text_requests` for `_render_bar`'s standalone case,
    a list threaded through the whole combo render for the layered
    case) -- this function never draws text directly itself, the same
    "collect while drawing shapes, replay afterward" split every other
    render path here uses (see `_TextRequest`'s own docstring).

    Colored by sign (`Theme.color_by_sign`) and labeled per bar
    (`Theme.show_data_labels`) exactly like a standalone `Mark.BAR`
    render -- both are plain `Theme` flags this function reads off
    `plot._theme` itself (via its own `_Scaled(theme)`, not whatever
    scale the caller's own frame happened to use -- a layered bar's
    label sizing follows its *own* `Theme.scale`, the same per-layer
    styling independence `_render_bar_combo_layers`'s other layers
    already have), unaffected by whether the caller is `_render_bar`
    or a layered combo.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var baseline_py = _axis_pixel(y_scale, 0.0)
    # bandwidth() depends only on the scale's domain length and
    # pixel range, never on the category index -- hoisted here (and in
    # every other mark's loop) rather than recomputing its division
    # once per category.
    var bar_width = _round_to_int(x_scale.bandwidth())
    for i in range(len(plot.x_categories)):
        var bar_x = _round_to_int(x_scale.band_start(i))
        var top_py = _axis_pixel(y_scale, plot.y_data[i])
        var rect = _pull_off_axis_line(baseline_py, top_py, py1)
        var bar_color = (
            theme.mark_color_negative
            if (theme.color_by_sign and plot.y_data[i] < 0.0)
            else theme.mark_color
        )
        target.fill_rect(bar_x, rect.y, bar_width, rect.height, bar_color)
        if theme.show_data_labels:
            # Positive value: baseline sits label_gap above the bar's
            # own top edge (rect.y), the same "baseline placed where
            # the text should visually end up, not its top" convention
            # _draw_annotation_points's label uses. Negative value:
            # below the bar's bottom edge instead (rect.y + rect.
            # height), mirroring the "below" placement every category
            # tick label on this same axis already uses (frame.py1 +
            # tick_length + label_gap + font_size) -- a bar that
            # extends downward gets its label below it, not colliding
            # with the bar itself.
            var label_y = (
                rect.y + rect.height + sc.label_gap + Int(sc.font_size)
                if plot.y_data[i] < 0.0
                else rect.y - sc.label_gap
            )
            text_requests.append(
                _TextRequest(
                    bar_x + bar_width // 2,
                    label_y,
                    _format_fixed(plot.y_data[i], _label_decimals(plot.y_data[i])),
                    theme.text_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )


def _render_bar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.BAR` plot: a categorical x-axis (`OrdinalScale`,
    one evenly spaced band per category) and a continuous y-axis whose
    domain always includes a zero baseline (`_zero_baseline_y_extent`,
    not the padded-around-the-data-only `_data_extent` the continuous marks
    use). Generic over `T: DrawTarget`, returning axis/tick labels as
    `_TextRequest`s rather than drawing them -- see `_render_generic`'s docstring for why every render path here works this way.

    `ox0`/`oy0`/`ox1`/`oy1` are `render()`'s already-resolved outer
    bounds (never the -1 sentinel by the time they reach here -- see
    `render()`'s docstring) -- this function never reads a target's width/height directly, so it lays out relative to whatever
    rectangle it was given, the whole target or one facet cell alike.

    The axis frame itself (`OrdinalScale`, gridlines, axis lines, every
    tick+label) is `_draw_categorical_axis_frame`'s job, shared
    with `Mark.LOLLIPOP`/`WATERFALL`/`BOX` -- see that function's
    docstring for the shared frame's behavior. What's left here is
    exactly the one genuinely BAR-specific thing: filling each
    category's rect from a zero baseline to its value (`_draw_bar_
    rects`, shared with `render_layers()`'s bar-combo path -- see that
    function's own docstring for why it's factored out).

    `Theme.show_data_labels` (default `False`) draws each bar's own
    value as text above it (below it for a negative value, so the
    label never collides with a bar that extends downward) -- see
    that field's own docstring.

    No x-gridlines (unlike the continuous path's per-tick vertical
    gridlines) -- the bars themselves already visually separate
    categories, so a vertical gridline per bar wouldn't add
    information the way it does for a continuous scatter/line axis.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    # y-domain computed before the frame's dynamic left margin is
    # finalized -- see _draw_categorical_axis_frame's docstring for
    # why it takes y_scale as an input rather than computing it itself.
    var y_scale = _zero_baseline_y_extent(plot.y_data)
    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    _draw_bar_rects(target, plot, frame.x_scale, frame.y_scale, frame.py1, frame.text_requests)

    # A `.copy()`, not a `^` transfer -- Mojo's ownership checker
    # rejects moving a single field out of `frame` at all (even here,
    # its last use): "field 'frame.text_requests' destroyed out of the
    # middle of a value" -- `frame` as a whole still owns `x_scale`/
    # `y_scale`/`sc`, which need their normal end-of-scope
    # destruction, not a partial one. A small List copy here is a cheap
    # trade for not having to hand-unpack every field `_CategoricalFrame`
    # carries just to satisfy this.
    return frame.result()


def _draw_horizontal_bar_rects[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    x_scale: LinearScale,
    y_scale: OrdinalScale,
    px0: Int,
    mut text_requests: List[_TextRequest],
) raises:
    """`_draw_bar_rects`'s mirror image for a horizontal `Mark.BAR`
    (`Plot.mark_bar(horizontal=True)`, #121) -- categories run down the
    `y_scale` (`OrdinalScale`) instead of across an x-axis, and each
    bar is a horizontal rect extending from a zero baseline along the
    continuous `x_scale` (`LinearScale`) instead of a vertical one.
    Every role `_draw_bar_rects` gives `x_scale`/`bar_x`/`bar_width`
    here belongs to `y_scale`/`bar_y`/`bar_height` instead, and vice
    versa -- otherwise the exact same logic, including `Theme.color_
    by_sign`/`show_data_labels` support.

    `px0` is the frame's own *left* pixel column -- `_pull_off_axis_
    line`'s "don't paint over the axis line's antialiasing" check
    needs it here instead of `_draw_bar_rects`'s `py1` (the bottom
    row), since a horizontal bar's zero baseline can land on the
    vertical categorical axis line drawn at the frame's left edge, the
    exact rotated equivalent of a vertical bar's baseline landing on
    the horizontal axis line at the bottom.

    Not shared with `render_layers()`'s bar-combo path the way `_draw_
    bar_rects` is -- `_render_bar_combo_layers` raises clearly on a
    horizontal bar layer instead (see its own docstring) rather than
    trying to lay out a horizontal categorical axis alongside
    continuous line/point/area layers, a real, separate feature this
    doesn't attempt.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var baseline_px = _axis_pixel(x_scale, 0.0)
    # bandwidth() depends only on the scale's domain length and pixel
    # range, never on the category index -- hoisted here exactly like
    # _draw_bar_rects' own bar_width.
    var bar_height = _round_to_int(y_scale.bandwidth())
    for i in range(len(plot.x_categories)):
        var bar_y = _round_to_int(y_scale.band_start(i))
        var value_px = _axis_pixel(x_scale, plot.y_data[i])
        var rect = _pull_off_axis_line(baseline_px, value_px, px0)
        var bar_color = (
            theme.mark_color_negative
            if (theme.color_by_sign and plot.y_data[i] < 0.0)
            else theme.mark_color
        )
        target.fill_rect(rect.y, bar_y, rect.height, bar_height, bar_color)
        if theme.show_data_labels:
            # Positive value (bar extends right): label sits label_gap
            # to the right of the bar's own right edge, left-aligned --
            # the horizontal-axis mirror of _draw_bar_rects' "above the
            # bar" placement. Negative value (bar extends left): to the
            # left of the bar's left edge instead, right-aligned, so
            # the label never collides with a bar that extends left of
            # the baseline. Vertically centered on the bar's own row
            # (TextAlign has no vertical option -- the same `font_size
            # * 0.35` baseline-centering offset treemap.mojo/sankey.mojo/
            # stacked_bar.mojo's own labels already use).
            var label_x = (
                rect.y - sc.label_gap
                if plot.y_data[i] < 0.0
                else rect.y + rect.height + sc.label_gap
            )
            var label_align = TextAlign.RIGHT if plot.y_data[i] < 0.0 else TextAlign.LEFT
            text_requests.append(
                _TextRequest(
                    label_x,
                    bar_y + bar_height // 2 + Int(sc.font_size * 0.35),
                    _format_fixed(plot.y_data[i], _label_decimals(plot.y_data[i])),
                    theme.text_color,
                    sc.font_size,
                    label_align,
                    theme.font_family,
                )
            )


def _render_horizontal_bar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """`_render_bar`'s mirror image for `Plot.mark_bar(horizontal=True)`
    (#121): a categorical y-axis (`OrdinalScale`, one evenly spaced
    band per category, top to bottom) and a continuous x-axis whose
    domain always includes a zero baseline (`_zero_baseline_y_extent`
    -- axis-agnostic despite the name, see its own docstring; the same
    function `_render_bar` uses for its own y-domain, reused here for
    an x-domain instead).

    Deliberately a whole separate function from `_render_bar`, not an
    orientation flag threaded through it -- the same "a mark-type
    branch through nearly every line is worse than each path staying
    its function" reasoning `_draw_horizontal_categorical_axis_frame`'s
    own docstring already gives for why *that* function stays unshared
    from `_draw_categorical_axis_frame` (which scale is which type,
    which axis reverses, which margin grows dynamically -- exactly the
    branches a bidirectional version would need on nearly every line).

    The axis frame itself is `_draw_horizontal_categorical_axis_frame`'s
    job (gantt.mojo) -- already shared by `Mark.GANTT`/
    `POPULATION_PYRAMID`/`RIDGELINE` before this became its fourth
    caller, not new machinery built for this. What's left here is the
    one genuinely bar-specific thing, `_draw_horizontal_bar_rects`
    (this file), the exact mirror of `_render_bar`'s own `_draw_bar_
    rects` call.

    No y-gridlines (the horizontal mirror of `_render_bar`'s own "no
    x-gridlines" -- the bars themselves already visually separate
    categories).
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var x_scale = _zero_baseline_y_extent(plot.y_data)
    var frame = _draw_horizontal_categorical_axis_frame(
        target, plot.x_categories, x_scale, theme, ox0, oy0, ox1, oy1
    )

    _draw_horizontal_bar_rects(target, plot, frame.x_scale, frame.y_scale, frame.px0, frame.text_requests)

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
    """A bar chart -- `Mark.BAR` over a categorical `x` and continuous
    `y` (see `Plot.encode_categorical()`'s docstring; one bar per
    entry, negative values extend below the zero baseline
    automatically).

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
    var plot = Plot().mark_bar(horizontal=horizontal).encode_categorical(x=categories, y=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


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
    """`bar()`, generalized over numeric element type (`List[Int]`,
    `List[Float32]`, ...) instead of a concrete `List[Float64]` -- see
    `scatter()`'s own `DType`-generic overload (plot.mojo) for the
    full reasoning. Delegates to the concrete `bar()` above.
    """
    return bar(
        categories, _materialize_scalar_list(values), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title, horizontal=horizontal,
    )
