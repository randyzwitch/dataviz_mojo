"""Mark.BAR's own rendering -- see Plot.mark_bar()'s own docstring
(plot.mojo) for what the mark means; `_render_bar` is what `_render_
generic` (plot.mojo) dispatches to.
"""

from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget

from dataviz_mojo.mark import Mark
from dataviz_mojo.ordinal_scale import OrdinalScale
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _empty_result,
    _zero_baseline_y_extent,
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
    `_TextRequest`s rather than drawing them -- see `_render_generic`'s
    own docstring for why every render path here works this way.

    `ox0`/`oy0`/`ox1`/`oy1` are `render()`'s own already-resolved outer
    bounds (never the -1 sentinel by the time they reach here -- see
    `render()`'s own docstring) -- this function never reads a target's
    own width/height directly, so it lays out relative to whatever
    rectangle it was given, the whole target or one facet cell alike.

    The axis frame itself (`OrdinalScale`, gridlines, axis lines, every
    tick+label) is `_draw_categorical_axis_frame`'s job now, shared
    with `Mark.LOLLIPOP`/`WATERFALL`/`BOX` -- see that function's own
    docstring for why sharing became the right call, and for the one
    real (harmless) behavioral difference from this function's
    original, fully self-contained body. What's left here is exactly
    the one genuinely BAR-specific thing: filling each category's own
    rect from a zero baseline to its value, optionally colored by sign
    (`Theme.color_by_sign`).

    No x-gridlines (unlike the continuous path's per-tick vertical
    gridlines) -- the bars themselves already visually separate
    categories, so a vertical gridline per bar wouldn't add
    information the way it does for a continuous scatter/line axis.
    """
    if len(plot.x_categories) != len(plot.y_data):
        raise Error(
            "Plot.encode_categorical(): x and y must have the same length"
            " (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot.y_data))
            + ")"
        )

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    # y-domain computed before the frame's own dynamic left margin is
    # finalized -- see _draw_categorical_axis_frame's own docstring for
    # why it takes y_scale as an input rather than computing it itself.
    var y_scale = _zero_baseline_y_extent(plot.y_data)
    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    var baseline_py = _axis_pixel(frame.y_scale, 0.0)
    for i in range(len(plot.x_categories)):
        var bar_x = _round_to_int(frame.x_scale.band_start(i))
        var bar_width = _round_to_int(frame.x_scale.bandwidth())
        var top_py = _axis_pixel(frame.y_scale, plot.y_data[i])
        var bar_y = min(baseline_py, top_py)
        var bar_height = max(baseline_py, top_py) - min(baseline_py, top_py)
        var bar_color = (
            theme.mark_color_negative
            if (theme.color_by_sign and plot.y_data[i] < 0.0)
            else theme.mark_color
        )
        target.fill_rect(bar_x, bar_y, bar_width, bar_height, bar_color)

    # A `.copy()`, not a `^` transfer -- Mojo's ownership checker
    # rejects moving a single field out of `frame` at all (even here,
    # its last use): "field 'frame.text_requests' destroyed out of the
    # middle of a value" -- `frame` as a whole still owns `x_scale`/
    # `y_scale`/`sc`, which need their own normal end-of-scope
    # destruction, not a partial one. A small List copy here is a cheap
    # trade for not having to hand-unpack every field `_CategoricalFrame`
    # carries just to satisfy this.
    return frame.result()
