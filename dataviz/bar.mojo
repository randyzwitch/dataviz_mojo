from canvas.color import Color
from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list

from canvas.text.render import TextAlign
from dataviz.ordinal_scale import OrdinalScale
from dataviz.scale import LinearScale, _format_fixed, _label_decimals
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Orientation,
    _Scaled,
    _tooltip_label,
    _TextRequest,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _empty_result,
    _pull_off_axis_line,
    _finished,
    _zero_baseline_y_extent,
    _validate_categorical_encoding,
)
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.theme import Theme


def _bar_fill_color(theme: Theme, value: Float64) -> Color:
    """The one fill color `_draw_bar_rects`
    both pick per bar -- `Theme.mark_color_negative` when `Theme.
    color_by_sign` is on and this bar's own value is negative, `Theme.
    mark_color` otherwise. Color doesn't depend on which axis is
    which, so both orientations share this instead of each inlining
    the same ternary.
    """
    return theme.mark_color_negative if (theme.color_by_sign and value < 0.0) else theme.mark_color


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
    """Draw one `Mark.BAR` plot's rectangles (and, when `Theme.show_
    data_labels` is set, each one's value label) into an already-laid-
    out categorical axis frame -- written once for both orientations,
    with `_Orientation` carrying the only two differences (which way a
    rect is emitted, where its label sits).

    Factored out of `_render_bar` so `render_layers()`'s bar-combo path
    (`_render_bar_combo_layers`, plot.mojo) can draw a `Mark.BAR` layer
    against a frame *it* built, shared across every layer, instead of
    `_render_bar` building its own standalone one -- the same "share
    the drawing primitive, not just the layout" split `_draw_point_
    layer`/`_draw_line_layer`/`_draw_area_layer` (plot.mojo) already
    use for the continuous marks. That combo path is vertical-only and
    passes `_Orientation(False)`; it raises on a horizontal bar layer
    rather than trying to lay out a horizontal categorical axis
    alongside continuous line/point/area layers.

    `band_scale`/`value_scale` come from whichever frame the caller
    built, and `baseline_edge` is that frame's own axis line (`py1`
    vertically, `px0` horizontally) for `_pull_off_axis_line`'s
    don't-paint-over-the-antialiasing check.

    Colored by sign (`Theme.color_by_sign`) and labeled per bar
    (`Theme.show_data_labels`) off `plot._theme` itself, via this
    function's own `_Scaled(theme)` rather than whatever scale the
    caller's frame happened to use -- a layered bar's label sizing
    follows its *own* `Theme.scale`.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var baseline = _axis_pixel(value_scale, 0.0)
    # bandwidth() depends only on the scale's domain length and pixel
    # range, never on the category index -- hoisted rather than
    # recomputing its division once per category.
    var band_size = _round_to_int(band_scale.bandwidth())
    for i in range(len(plot.x_categories)):
        var band_pos = _round_to_int(band_scale.band_start(i))
        var value = plot.y_data[i]
        var extent = _pull_off_axis_line(baseline, _axis_pixel(value_scale, value), baseline_edge)
        if theme.svg_tooltips:
            target.begin_annotated_group(_tooltip_label(plot.x_categories[i], value))
        orient.fill_band_rect(target, extent, band_pos, band_size, _bar_fill_color(theme, value))
        if theme.svg_tooltips:
            target.end_annotated_group()
        if theme.show_data_labels:
            var at = orient.outside_band_label(
                extent, band_pos, band_size, value < 0.0, sc.label_gap, sc.font_size
            )
            text_requests.append(
                _TextRequest(
                    at.x,
                    at.y,
                    _format_fixed(value, _label_decimals(value)),
                    theme.text_color,
                    sc.font_size,
                    at.align,
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

    _draw_bar_rects(
        target, plot, frame.x_scale, frame.y_scale, frame.py1, _Orientation(False), frame.text_requests
    )

    # A `.copy()`, not a `^` transfer -- Mojo's ownership checker
    # rejects moving a single field out of `frame` at all (even here,
    # its last use): "field 'frame.text_requests' destroyed out of the
    # middle of a value" -- `frame` as a whole still owns `x_scale`/
    # `y_scale`/`sc`, which need their normal end-of-scope
    # destruction, not a partial one. A small List copy here is a cheap
    # trade for not having to hand-unpack every field `_CategoricalFrame`
    # carries just to satisfy this.
    return frame.result()


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
    That reasoning covers the *frame* only: the rect drawing itself is
    shared, since `_Orientation` isolates the two places it differs.

    The axis frame itself is `_draw_horizontal_categorical_axis_frame`'s
    job (gantt.mojo) -- already shared by `Mark.GANTT`/
    `POPULATION_PYRAMID`/`RIDGELINE` before this became its fourth
    caller, not new machinery built for this. What's left here is the
    one genuinely bar-specific thing, `_draw_bar_rects` (this file) --
    the same call `_render_bar` makes, differing only in which of the
    frame's two scales is the band one and an `_Orientation(True)`.

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

    _draw_bar_rects(
        target, plot, frame.y_scale, frame.x_scale, frame.px0, _Orientation(True), frame.text_requests
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
