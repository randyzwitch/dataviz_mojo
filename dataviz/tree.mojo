from canvas.geometry import _round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.hierarchy import _HierarchyIndex, _build_hierarchy_index
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_legend,
    _dynamic_legend_width,
    _empty_result,
    _finished,
    _require_non_negative,
)
from dataviz.theme import Theme


def _assign_leaf_positions(node: Int, idx: _HierarchyIndex, mut x: List[Float64], next_leaf: Int) -> Int:
    """A simplified tree layout, not Reingold-Tilford (which also shifts
    whole subtrees sideways to avoid overlap between unevenly shaped
    siblings). Every leaf gets the next sequential integer x-slot, left
    to right in `idx.children`'s sibling order; `next_leaf` is threaded
    through the return value rather than a shared mutable counter. Every
    internal node's x-slot is the average of its children's, which can
    overlap two unrelated subtrees' leaves in a lopsided tree.
    """
    if len(idx.children[node]) == 0:
        x[node] = Float64(next_leaf)
        return next_leaf + 1
    var n = next_leaf
    var child_x_sum = 0.0
    for c in idx.children[node]:
        n = _assign_leaf_positions(c, idx, x, n)
        child_x_sum += x[c]
    x[node] = child_x_sum / Float64(len(idx.children[node]))
    return n


def _assign_branch_colors(node: Int, branch: Int, idx: _HierarchyIndex, mut out: List[Int]):
    """Every node in `node`'s subtree gets the same `branch` index (the
    root's direct children are numbered 0, 1, 2, ... by `_render_tree`),
    the same one-color-per-top-level-branch convention `Mark.SUNBURST`
    uses. Computed once into a `List[Int]` rather than threaded through a
    draw recursion, because `Mark.TREE` draws edges and markers in two
    separate passes.

    Walks an explicit worklist rather than recursing: order doesn't
    matter, it can't exhaust the stack on a deep tree, and it avoids the
    compiler's "self recursive call will cause an infinite loop" false
    positive. Termination is guaranteed by `_build_hierarchy_index`
    (hierarchy.mojo), which rejects cycles and disconnected components.
    """
    var pending = List[Int]()
    pending.append(node)
    while len(pending) > 0:
        var current = pending.pop()
        out[current] = branch
        for c in idx.children[current]:
            pending.append(c)


def _tree_node_x(leaf_x: Float64, num_leaves: Int, plot_x0: Int, plot_x1: Int) -> Float64:
    """A node's pixel x from its `_assign_leaf_positions` slot: slot `0` at
    `plot_x0`, slot `num_leaves - 1` at `plot_x1`, linear between (an
    internal node's fractional slot lands proportionally). A single-leaf
    tree centers.
    """
    if num_leaves <= 1:
        return Float64(plot_x0 + plot_x1) / 2.0
    return Float64(plot_x0) + (leaf_x / Float64(num_leaves - 1)) * Float64(plot_x1 - plot_x0)


def _tree_node_y(depth: Int, max_depth: Int, plot_y0: Int, plot_y1: Int) -> Float64:
    """A node's pixel y from its `depth`: depth 0 at `plot_y0`, `max_depth`
    at `plot_y1`. A single-node tree pins to the top.
    """
    if max_depth <= 0:
        return Float64(plot_y0)
    return Float64(plot_y0) + (Float64(depth) / Float64(max_depth)) * Float64(plot_y1 - plot_y0)


def _render_tree[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.TREE` plot: `_build_hierarchy_index`'s `children`/
    `depth` (hierarchy.mojo) laid out top-to-bottom (root at the top,
    `depth` picks each node's row) with `_assign_leaf_positions`'s
    horizontal placement, as a node-link diagram.

    Two passes rather than one recursive draw: every edge (a straight line
    from each non-root node to its parent) first, then every node marker
    (a filled circle) plus its label, so no marker is drawn under an edge.
    Edge and marker color follow `_assign_branch_colors`'s
    per-top-level-branch assignment; the root stays `Theme.text_color`.

    Every value must be non-negative, for consistency with the other
    `encode_hierarchy()` marks, even though the tree layout never reads
    `values`.
    """
    if (
        len(plot._hierarchy.parent_ids) != len(plot._hierarchy.ids)
        or len(plot._hierarchy.values) != len(plot._hierarchy.ids)
    ):
        raise Error(
            "Plot.encode_hierarchy(): ids, parent_ids, and values must all have the"
            " same length (got "
            + String(len(plot._hierarchy.ids))
            + " ids, "
            + String(len(plot._hierarchy.parent_ids))
            + " parent_ids, "
            + String(len(plot._hierarchy.values))
            + " values)"
        )

    var theme = plot._theme
    if len(plot._hierarchy.ids) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    _require_non_negative(plot._hierarchy.values, "Mark.TREE")

    var idx = _build_hierarchy_index(plot._hierarchy.ids, plot._hierarchy.parent_ids, plot._hierarchy.values)
    var n = len(plot._hierarchy.ids)

    var parent_row = List[Int](capacity=n)
    for _ in range(n):
        parent_row.append(-1)
    for p in range(n):
        for c in idx.children[p]:
            parent_row[c] = p

    var leaf_x = List[Float64](capacity=n)
    for _ in range(n):
        leaf_x.append(0.0)
    var num_leaves = _assign_leaf_positions(idx.root, idx, leaf_x, 0)

    var branch = List[Int](capacity=n)
    for _ in range(n):
        branch.append(-1)
    var root_children = idx.children[idx.root].copy()
    for i in range(len(root_children)):
        _assign_branch_colors(root_children[i], i, idx, branch)

    var text_requests = List[_TextRequest]()
    var legend_labels = List[String]()
    for c in root_children:
        legend_labels.append(plot._hierarchy.ids[c])

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _dynamic_legend_width(legend_labels, sc.legend_swatch_size, sc) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom

    var palette = default_categorical_palette()

    for row in range(n):
        if row == idx.root:
            continue
        var color = palette[branch[row] % len(palette)] if branch[row] >= 0 else theme.text_color
        var px0 = _round_to_int(
            _tree_node_x(leaf_x[parent_row[row]], num_leaves, plot_x0, plot_x1)
        )
        var py0 = _round_to_int(
            _tree_node_y(idx.depth[parent_row[row]], idx.max_depth, plot_y0, plot_y1)
        )
        var px1 = _round_to_int(_tree_node_x(leaf_x[row], num_leaves, plot_x0, plot_x1))
        var py1 = _round_to_int(_tree_node_y(idx.depth[row], idx.max_depth, plot_y0, plot_y1))
        target.draw_line_aa(px0, py0, px1, py1, color, sc.line_width)

    for row in range(n):
        var color = palette[branch[row] % len(palette)] if branch[row] >= 0 else theme.text_color
        var px = _round_to_int(_tree_node_x(leaf_x[row], num_leaves, plot_x0, plot_x1))
        var py = _round_to_int(_tree_node_y(idx.depth[row], idx.max_depth, plot_y0, plot_y1))
        target.fill_circle_aa(px, py, _round_to_int(sc.point_radius), color)
        text_requests.append(
            _TextRequest(
                px, py + sc.tick_length + sc.label_gap + Int(sc.font_size), plot._hierarchy.ids[row],
                theme.text_color, sc.font_size, TextAlign.CENTER, theme.font_family,
            )
        )

    if show_legend:
        _draw_legend(target, text_requests, legend_labels, palette, plot_x1 + sc.margin_right, plot_y0, theme)

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def tree(
    ids: List[String],
    parent_ids: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A tree diagram.

    `Mark.TREE`: a hierarchy (`Plot.encode_hierarchy()`'s flattened
    `ids`/`parent_ids`/`values`) drawn as a top-to-bottom node-link
    diagram. See `_render_tree`.

    Args:
        ids: Every node's unique id, flattened (not nested), one
            entry per node.
        parent_ids: Each node's parent id (must be a value present in
            `ids`, or empty for the single root); paired with
            `ids[i]`.
        values: Each leaf node's magnitude (unused by `tree()`'s own
            layout, but still validated non-negative -- see `Plot.
            encode_hierarchy()`'s docstring).
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
        from dataviz import tree
        from dataviz.plot import save

        def main() raises:
            var ids: List[String] = [
                "CEO", "Engineering", "Sales", "Backend", "Frontend", "Enterprise", "SMB",
            ]
            var parent_ids: List[String] = ["", "CEO", "CEO", "Engineering", "Engineering", "Sales", "Sales"]
            var values: List[Int] = [0, 0, 0, 1, 1, 1, 1]

            var c = tree(ids, parent_ids, values)
            save(c, "docs/src/examples/out_tree.svg")
        ```
    """
    var plot = Plot().mark_tree().encode_hierarchy(ids=ids, parent_ids=parent_ids, values=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def tree[
    dtype: DType
](
    ids: List[String],
    parent_ids: List[String],
    values: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`tree()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return tree(
        ids, parent_ids, _materialize_scalar_list(values), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
