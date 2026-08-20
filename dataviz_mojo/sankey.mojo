from canvas_mojo.color import Color
from canvas_mojo.geometry import _round_to_int
from canvas_mojo.path import Path
from canvas_mojo.text.render import TextAlign
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _empty_result,
    _index_of,
    _rendered,
    _unique_categories,
)
from dataviz_mojo.theme import Theme

comptime _SANKEY_NODE_WIDTH = 12.0
"""Each node's own fixed pixel width (scaled by `_Scaled.scale`, the
same convention every other raw-pixel-quantity constant in this
package follows) -- a Sankey node is a thin bar, not a shape whose own
width means anything (unlike its height, which is real, value-derived
data). Fixed, not a `Theme` field, the usual "no concrete need for a
knob yet" reasoning."""


def _render_sankey[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.SANKEY` plot: `Mark.CHORD`'s own edge-list shape
    (`encode_chord()`'s `from`/`to`/`value`) reused unchanged again,
    laid out left-to-right by column (a node's own column is the
    length of the *longest* path reaching it from any source -- a node
    with no incoming edges -- computed via one Kahn's-algorithm
    topological pass over the edge list; a cycle makes that
    impossible, so this raises rather than looping forever if the
    given edges aren't a real DAG, which every real Sankey's own flow
    data already has to be).

    Each node draws as a thin vertical bar, height proportional to
    `max(total inflow, total outflow)` (so a node's own imbalance
    between the two, if any, is visible: whichever side sums to less
    than the node's own full height leaves a real gap, not silently
    stretched to hide it). Nodes sharing a column stack top-to-bottom,
    each claiming `own value / column's own total value` of the
    column's own available height -- the same "round the cumulative
    boundary, not an independent size" pattern `Mark.MARIMEKKO`/
    `TREEMAP` already establish, so adjacent nodes in a column never
    show a hairline gap.

    Each flow draws as a filled quadrilateral ("ribbon") between a
    slice of its own `from` node's right edge and a slice of its own
    `to` node's left edge -- straight edges, not a smooth curve (the
    same "straight, not curved" simplification `Mark.CHORD`'s own
    straight-rim ribbons already are, for the identical reason: a
    smooth Bezier ribbon whose own top and bottom edges both curve
    independently is real, added geometric complexity a straight
    trapezoid sidesteps while keeping the same essential "value ->
    proportional width" reading). Ribbons connect straight to their
    own target column's own x, regardless of how many columns apart
    the two nodes are -- a "skip" edge (source column 0 directly to a
    column-2 node) draws straight through whatever's visually in
    column 1, not rerouted around it, a real v1 scope limit. Multiple
    flows in or out of one node stack in the given row order, each
    claiming its own proportional slice of that node's own side --
    exactly how a real Sankey's own additive-flow reading works.

    A self-loop (`from[i] == to[i]`) is dropped before layout entirely
    (not just left undrawn the way `Mark.ARC_DIAGRAM`/`GRAPH` handle
    it) -- a self-loop has no meaningful column-distance to lay out in
    the first place. Every value must be non-negative.
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
            raise Error("Plot: Mark.SANKEY values must be non-negative (got " + String(v) + ")")

    var combined = List[String]()
    for v in plot._chord_from:
        combined.append(v)
    for v in plot._chord_to:
        combined.append(v)
    var nodes = _unique_categories(combined)
    var n = len(nodes)

    var from_idx = List[Int](capacity=len(plot._chord_from))
    var to_idx = List[Int](capacity=len(plot._chord_from))
    var edge_value = List[Float64](capacity=len(plot._chord_from))
    var children = List[List[Int]]()
    var in_degree = List[Int]()
    for _ in range(n):
        children.append(List[Int]())
        in_degree.append(0)
    for row in range(len(plot._chord_from)):
        var fi = _index_of(nodes, plot._chord_from[row])
        var ti = _index_of(nodes, plot._chord_to[row])
        if fi == ti:
            continue
        from_idx.append(fi)
        to_idx.append(ti)
        edge_value.append(plot._chord_value[row])
        children[fi].append(ti)
        in_degree[ti] += 1

    var column = List[Int](capacity=n)
    for _ in range(n):
        column.append(0)
    var remaining_in = in_degree.copy()
    var queue = List[Int]()
    for i in range(n):
        if remaining_in[i] == 0:
            queue.append(i)
    var qi = 0
    while qi < len(queue):
        var node = queue[qi]
        qi += 1
        for c in children[node]:
            if column[node] + 1 > column[c]:
                column[c] = column[node] + 1
            remaining_in[c] -= 1
            if remaining_in[c] == 0:
                queue.append(c)
    if len(queue) != n:
        raise Error(
            "Plot: Mark.SANKEY requires the edges to form a DAG (a cycle was found --"
            " every real Sankey diagram's own flow data must have no cycles)"
        )

    var max_column = 0
    for c in column:
        if c > max_column:
            max_column = c

    var total_in = List[Float64](capacity=n)
    var total_out = List[Float64](capacity=n)
    for _ in range(n):
        total_in.append(0.0)
        total_out.append(0.0)
    for e in range(len(from_idx)):
        total_out[from_idx[e]] += edge_value[e]
        total_in[to_idx[e]] += edge_value[e]
    var node_value = List[Float64](capacity=n)
    for i in range(n):
        node_value.append(max(total_in[i], total_out[i]))

    var sc = _Scaled(theme)
    var node_width = _SANKEY_NODE_WIDTH * sc.scale
    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom

    var col_x = List[Float64](capacity=max_column + 1)
    for c in range(max_column + 1):
        var frac = 0.5 if max_column == 0 else Float64(c) / Float64(max_column)
        col_x.append(Float64(plot_x0) + frac * Float64(plot_x1 - plot_x0 - Int(node_width)))

    var nodes_in_column = List[List[Int]]()
    for _ in range(max_column + 1):
        nodes_in_column.append(List[Int]())
    for i in range(n):
        nodes_in_column[column[i]].append(i)

    var node_y0 = List[Float64](capacity=n)
    var node_y1 = List[Float64](capacity=n)
    for _ in range(n):
        node_y0.append(0.0)
        node_y1.append(0.0)
    for c in range(max_column + 1):
        var members = nodes_in_column[c].copy()
        var col_total = 0.0
        for i in members:
            col_total += node_value[i]
        if col_total <= 0.0:
            continue
        var cum = 0.0
        for i in members:
            node_y0[i] = Float64(plot_y0) + cum / col_total * Float64(plot_y1 - plot_y0)
            cum += node_value[i]
            node_y1[i] = Float64(plot_y0) + cum / col_total * Float64(plot_y1 - plot_y0)

    var palette = default_categorical_palette()
    var out_cursor = node_y0.copy()
    var in_cursor = node_y0.copy()
    for e in range(len(from_idx)):
        var fi = from_idx[e]
        var ti = to_idx[e]
        var src_h = (edge_value[e] / node_value[fi]) * (node_y1[fi] - node_y0[fi]) if node_value[fi] > 0.0 else 0.0
        var src_top = out_cursor[fi]
        var src_bottom = src_top + src_h
        out_cursor[fi] = src_bottom

        var tgt_h = (edge_value[e] / node_value[ti]) * (node_y1[ti] - node_y0[ti]) if node_value[ti] > 0.0 else 0.0
        var tgt_top = in_cursor[ti]
        var tgt_bottom = tgt_top + tgt_h
        in_cursor[ti] = tgt_bottom

        var src_x = col_x[column[fi]] + node_width
        var tgt_x = col_x[column[ti]]

        var path = Path()
        path.move_to(src_x, src_top)
        path.line_to(src_x, src_bottom)
        path.line_to(tgt_x, tgt_bottom)
        path.line_to(tgt_x, tgt_top)
        path.close()
        target.fill_path_aa(path, palette[fi % len(palette)])

    var text_requests = List[_TextRequest]()
    for i in range(n):
        var x = _round_to_int(col_x[column[i]])
        var y0 = _round_to_int(node_y0[i])
        var h = max(1, _round_to_int(node_y1[i]) - y0)
        target.fill_rect(x, y0, _round_to_int(node_width), h, palette[i % len(palette)])
        var label_x = x + _round_to_int(node_width) + sc.label_gap
        var label_y = y0 + h // 2 + Int(sc.font_size * 0.35)
        text_requests.append(_TextRequest(label_x, label_y, nodes[i], theme.text_color, sc.font_size, TextAlign.LEFT))

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def sankey(
    from_categories: List[String],
    to_categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A Sankey diagram -- `Mark.SANKEY`, `Mark.CHORD`'s own edge list
    (`Plot.encode_chord()`'s `from_categories`/`to_categories`/
    `values`) drawn as nodes in left-to-right columns connected by
    proportionally sized flow ribbons. The edges must form a DAG (no
    cycles) -- see `_render_sankey`'s own docstring for the full
    reasoning."""
    var plot = Plot().mark_sankey().encode_chord(
        from_categories=from_categories, to_categories=to_categories, values=values
    )
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
