from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.mark import Mark
from dataviz_mojo.ordinal_scale import OrdinalScale
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _empty_result,
    _pull_off_axis_line,
    _rendered,
    _zero_baseline_y_extent,
    _validate_categorical_encoding,
)
from dataviz_mojo.theme import Theme


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
    category's rect from a zero baseline to its value, optionally
    colored by sign (`Theme.color_by_sign`) -- pulled 1px off the axis
    line via `_pull_off_axis_line` wherever the baseline lands on it
    (see that function's docstring).

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

    var baseline_py = _axis_pixel(frame.y_scale, 0.0)
    # bandwidth() depends only on the scale's domain length and
    # pixel range, never on the category index -- hoisted here (and in
    # every other mark's loop) rather than recomputing its division
    # once per category.
    var bar_width = _round_to_int(frame.x_scale.bandwidth())
    for i in range(len(plot.x_categories)):
        var bar_x = _round_to_int(frame.x_scale.band_start(i))
        var top_py = _axis_pixel(frame.y_scale, plot.y_data[i])
        var rect = _pull_off_axis_line(baseline_py, top_py, frame.py1)
        var bar_color = (
            theme.mark_color_negative
            if (theme.color_by_sign and plot.y_data[i] < 0.0)
            else theme.mark_color
        )
        target.fill_rect(bar_x, rect.y, bar_width, rect.height, bar_color)

    # A `.copy()`, not a `^` transfer -- Mojo's ownership checker
    # rejects moving a single field out of `frame` at all (even here,
    # its last use): "field 'frame.text_requests' destroyed out of the
    # middle of a value" -- `frame` as a whole still owns `x_scale`/
    # `y_scale`/`sc`, which need their normal end-of-scope
    # destruction, not a partial one. A small List copy here is a cheap
    # trade for not having to hand-unpack every field `_CategoricalFrame`
    # carries just to satisfy this.
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
) raises -> Canvas:
    """A bar chart -- `Mark.BAR` over a categorical `x` and continuous
    `y` (see `Plot.encode_categorical()`'s docstring; one bar per
    entry, negative values extend below the zero baseline
    automatically)."""
    var plot = Plot().mark_bar().encode_categorical(x=categories, y=values)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
