from std.math import cos, pi, sin

from canvas_mojo.color import Color
from canvas_mojo.path import Path
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_legend,
    _dynamic_legend_width,
    _empty_result,
    _index_of,
    _rendered,
    _unique_categories,
)
from dataviz_mojo.theme import Theme

# The node ring's own thickness, as a fraction of the outer radius --
# fixed, not a Theme field: unlike Mark.ARC's donut_inner_radius_
# fraction (a real pie-vs-donut user choice), a chord diagram's ring
# is always a thin band the ribbons visually originate from, not a
# meaningful style choice with no concrete customization need yet
# (the same "fixed until a real need shows up" reasoning `_LEGEND_
# WIDTH`/every other module-level pixel constant here already follows).
comptime _CHORD_RING_FRACTION = 0.08

def _draw_chord_ribbon[
    T: DrawTarget
](mut target: T, cx: Float64, cy: Float64, r: Float64, a0: Float64, a1: Float64, b0: Float64, b1: Float64, color: Color) raises:
    """One ribbon: a filled shape bounded by two node-rim arcs (`a0`
    ->`a1` at node A's own inner radius, `b0`->`b1` at node B's) and
    two curved "cross" connections between them -- the classic chord-
    diagram ribbon shape. Each rim arc is a real `Path.arc_to` segment
    now (`canvas_mojo`'s own center/radius/angle convention matches
    this file's `cos`/`sin` rim-point math exactly, confirmed directly
    against `canvas_mojo`'s own `arc_to` docstring before relying on
    it -- no angle conversion needed at the call site); each cross
    connection is a single `quad_curve_to` pulled toward the circle's
    own center `(cx, cy)`, which bows every ribbon inward through the
    middle the way a real chord diagram's ribbons do, without needing
    per-ribbon control-point math of its own. `a0 <= a1`/`b0 <= b1`
    always hold here (`_render_chord`'s own angles only ever advance
    forward around the circle), matching `arc_to`'s own `start_angle <=
    end_angle` expectation.

    An earlier version of this function flattened each rim arc into
    short straight `line_to` segments by hand (`Path` had no arc-to
    command yet) -- see the git history/PR #25 for that version, and
    canvas_mojo's own PR #25 (`Path.arc_to`) for why it's gone. The
    ribbon's own visible shape is unchanged (`arc_to` traces the exact
    curve those segments were already approximating); the SVG backend
    gets a real payoff, though -- `SvgCanvas`'s own path output now
    emits a true elliptical-arc command for the rim instead of a
    polyline, so a chord diagram's own vector output is a real curve
    now, not a many-segment approximation of one.

    `r` is the *inner* radius of the node ring (`_render_chord`'s own
    `inner_radius`) -- ribbons visually originate from just inside the
    ring, not its outer edge, the standard chord-diagram look.
    """
    var path = Path()
    path.move_to(cx + r * cos(a0), cy + r * sin(a0))
    path.arc_to(cx, cy, r, a0, a1)
    path.quad_curve_to(cx, cy, cx + r * cos(b0), cy + r * sin(b0))
    path.arc_to(cx, cy, r, b0, b1)
    path.quad_curve_to(cx, cy, cx + r * cos(a0), cy + r * sin(a0))
    path.close()
    target.fill_path_aa(path, color)


def _render_chord[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.CHORD` plot: one node per distinct category
    across `encode_chord()`'s own `from`/`to` columns (`_unique_
    categories` over the two concatenated, first-seen order), arranged
    as ring sectors around a circle (`Mark.ARC`'s own start-at-12-
    o'clock, sweep-clockwise convention, reused exactly -- see `_render_
    arc`'s own docstring) sized by each node's own *total* flow (every
    value where it's the `from` or the `to`, so a node with several
    edges gets one contiguous arc, not several) -- then one ribbon per
    `from`/`to`/`value` row, connecting a sub-arc of its `from` node's
    own ring to a sub-arc of its `to` node's, each sub-arc sized `value
    / node's own total` of that node's full span (`_draw_chord_ribbon`).

    Sub-arcs are allocated in the order rows are given, each one
    advancing a per-node running angular cursor (`node_cursor`, starting
    at that node's own `node_start`) -- the same running-total
    bookkeeping style `Mark.WATERFALL`'s own `encode_waterfall` already
    established, just for angles instead of a bar's own running total.
    A self-loop (`from[i] == to[i]`) allocates two sub-arcs off the
    same node in sequence rather than one -- not specifically tested,
    but not rejected either, since nothing here assumes `from[i] !=
    to[i]`.

    Ribbons are colored by their own `from` node's palette color
    (`default_categorical_palette()`, the same index-by-node-position
    convention `Mark.ARC`'s own wedge coloring uses) -- a ribbon reads
    as "flow leaving this node," not a third, edge-specific color.
    """
    if len(plot._chord_from) != len(plot._chord_to) or len(plot._chord_value) != len(plot._chord_from):
        raise Error(
            "Plot.encode_chord(): from_categories, to_categories, and"
            " values must all have the same length (got "
            + String(len(plot._chord_from))
            + " from_categories, "
            + String(len(plot._chord_to))
            + " to_categories, "
            + String(len(plot._chord_value))
            + " values)"
        )

    var theme = plot._theme
    if len(plot._chord_from) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    for v in plot._chord_value:
        if v < 0.0:
            raise Error("Plot: Mark.CHORD values must be non-negative (got " + String(v) + ")")

    var combined = List[String]()
    for v in plot._chord_from:
        combined.append(v)
    for v in plot._chord_to:
        combined.append(v)
    var nodes = _unique_categories(combined)
    var n = len(nodes)

    var node_total = List[Float64]()
    for _ in range(n):
        node_total.append(0.0)
    var from_idx = List[Int]()
    var to_idx = List[Int]()
    for i in range(len(plot._chord_from)):
        var fi = _index_of(nodes, plot._chord_from[i])
        var ti = _index_of(nodes, plot._chord_to[i])
        from_idx.append(fi)
        to_idx.append(ti)
        node_total[fi] += plot._chord_value[i]
        node_total[ti] += plot._chord_value[i]

    var grand_total = 0.0
    for t in node_total:
        grand_total += t
    if grand_total <= 0.0:
        raise Error(
            "Plot: Mark.CHORD requires at least one positive value"
            " (every from/to node total summed to "
            + String(grand_total)
            + ")"
        )

    var node_start = List[Float64]()
    var node_end = List[Float64]()
    var cursor = -pi / 2.0
    for i in range(n):
        var span = (node_total[i] / grand_total) * 2.0 * pi
        node_start.append(cursor)
        node_end.append(cursor + span)
        cursor += span
    var node_cursor = node_start.copy()

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _dynamic_legend_width(nodes, sc.legend_swatch_size, sc) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    var inner_radius = radius * (1.0 - _CHORD_RING_FRACTION)

    var palette = default_categorical_palette()

    for i in range(len(plot._chord_from)):
        var fi = from_idx[i]
        var ti = to_idx[i]
        var value = plot._chord_value[i]
        var f0 = node_cursor[fi]
        var f1 = f0 + (value / grand_total) * 2.0 * pi
        node_cursor[fi] = f1
        var t0 = node_cursor[ti]
        var t1 = t0 + (value / grand_total) * 2.0 * pi
        node_cursor[ti] = t1
        _draw_chord_ribbon(target, cx, cy, inner_radius, f0, f1, t0, t1, palette[fi % len(palette)])

    for i in range(n):
        target.fill_ring_sector_aa(cx, cy, inner_radius, radius, node_start[i], node_end[i], palette[i % len(palette)])

    var text_requests = List[_TextRequest]()
    if show_legend:
        _draw_legend(target, text_requests, nodes, palette, plot_x1 + sc.margin_right, plot_y0, theme)

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def chord(
    from_categories: List[String],
    to_categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A chord diagram -- `Mark.CHORD`, ring sectors for every distinct
    node across `from_categories`/`to_categories`, connected by ribbons
    sized by `values`. See `Plot.encode_chord()`'s own docstring
    (plot.mojo) for the exact shape."""
    var plot = Plot().mark_chord().encode_chord(
        from_categories=from_categories, to_categories=to_categories, values=values
    )
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
