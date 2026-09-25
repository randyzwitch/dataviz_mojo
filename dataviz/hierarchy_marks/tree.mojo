from dataviz.chart import Chart
from dataviz.marks import Tree
from dataviz.core.chart_settings import _ChartSettings
from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats, _frame_strings
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.color_scale import categorical_palette_for
from dataviz.hierarchy_marks.hierarchy import (
    _HierarchyIndex,
    _build_hierarchy_index,
    _HierarchyData,
)
from dataviz.core.mark import Mark
from dataviz.plot import Plot, _finished
from dataviz.core.render_result import _RenderResult
from dataviz.core.text import _Scaled, _TextRequest
from dataviz.core.legend import _LegendLayout, _draw_legend_at, _legend_layout
from dataviz.core.validate import _require_non_negative
from dataviz.core.scale import _format_fixed, _label_decimals
from dataviz.core.theme import Theme


def _tree_node_label(
    ids: List[String], idx: _HierarchyIndex, row: Int
) -> String:
    """One node's hover text (#681): `"id: subtree total"` -- the id is
    already drawn beneath the node, but its value is not."""
    return (
        ids[row]
        + ": "
        + _format_fixed(
            idx.subtree_value[row], _label_decimals(idx.subtree_value[row])
        )
    )


def _assign_leaf_positions(
    node: Int, idx: _HierarchyIndex, mut x: List[Float64], next_leaf: Int
) -> Int:
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


def _assign_branch_colors(
    node: Int, branch: Int, idx: _HierarchyIndex, mut out: List[Int]
):
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


def _tree_node_x(
    leaf_x: Float64, num_leaves: Int, plot_x0: Int, plot_x1: Int
) -> Float64:
    """A node's pixel x from its `_assign_leaf_positions` slot: slot `0` at
    `plot_x0`, slot `num_leaves - 1` at `plot_x1`, linear between (an
    internal node's fractional slot lands proportionally). A single-leaf
    tree centers.
    """
    if num_leaves <= 1:
        return Float64(plot_x0 + plot_x1) / 2.0
    return Float64(plot_x0) + (leaf_x / Float64(num_leaves - 1)) * Float64(
        plot_x1 - plot_x0
    )


def _tree_node_y(
    depth: Int, max_depth: Int, plot_y0: Int, plot_y1: Int
) -> Float64:
    """A node's pixel y from its `depth`: depth 0 at `plot_y0`, `max_depth`
    at `plot_y1`. A single-node tree pins to the top.
    """
    if max_depth <= 0:
        return Float64(plot_y0)
    return Float64(plot_y0) + (Float64(depth) / Float64(max_depth)) * Float64(
        plot_y1 - plot_y0
    )


def _render_tree[
    T: DrawTarget
](
    mut target: T,
    hierarchy: _HierarchyData,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a hierarchy as a top-to-bottom node-link diagram.

    Depth selects rows and leaf placement determines x positions. Edges draw
    before nodes, colors follow top-level branches, and values must be
    non-negative.
    """
    if len(hierarchy.parent_ids) != len(hierarchy.ids) or len(
        hierarchy.values
    ) != len(hierarchy.ids):
        raise Error(
            "Plot.encode_hierarchy(): ids, parent_ids, and values must all have"
            " the same length (got "
            + String(len(hierarchy.ids))
            + " ids, "
            + String(len(hierarchy.parent_ids))
            + " parent_ids, "
            + String(len(hierarchy.values))
            + " values)"
        )

    var theme = settings.theme
    _require_non_negative(hierarchy.values, "Mark.TREE")

    var idx = _build_hierarchy_index(
        hierarchy.ids, hierarchy.parent_ids, hierarchy.values
    )
    var n = len(hierarchy.ids)

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
        legend_labels.append(hierarchy.ids[c])

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend = _legend_layout(
        legend_labels, sc.legend_swatch_size, sc, theme, ox1 - ox0, cache=cache
    ) if show_legend else _LegendLayout()

    var plot_x0 = ox0 + sc.margin_left + legend.left
    var plot_y0 = oy0 + sc.margin_top + legend.top
    var plot_x1 = ox1 - sc.margin_right - legend.right
    var plot_y1 = oy1 - sc.margin_bottom - legend.bottom

    var palette = categorical_palette_for(theme)

    for row in range(n):
        if row == idx.root:
            continue
        var color = (
            palette[branch[row] % len(palette)] if branch[row]
            >= 0 else theme.text_color
        )
        # A link is a diagonal between two laid-out node positions, so
        # nothing about it is crisper for being rounded -- and rounding
        # both ends independently tilted it away from the two nodes it
        # is meant to join.
        var px0 = _tree_node_x(
            leaf_x[parent_row[row]], num_leaves, plot_x0, plot_x1
        )
        var py0 = _tree_node_y(
            idx.depth[parent_row[row]], idx.max_depth, plot_y0, plot_y1
        )
        var px1 = _tree_node_x(leaf_x[row], num_leaves, plot_x0, plot_x1)
        var py1 = _tree_node_y(idx.depth[row], idx.max_depth, plot_y0, plot_y1)
        target.draw_line_aa(px0, py0, px1, py1, color, sc.line_width)

    var tooltips_on = settings.tooltips_on(n)
    for row in range(n):
        var color = (
            palette[branch[row] % len(palette)] if branch[row]
            >= 0 else theme.text_color
        )
        # Same position the links were drawn to, so a node and its links
        # meet exactly. The radius keeps rounding -- one constant for the
        # whole chart.
        var px = _tree_node_x(leaf_x[row], num_leaves, plot_x0, plot_x1)
        var py = _tree_node_y(idx.depth[row], idx.max_depth, plot_y0, plot_y1)
        if tooltips_on:
            target.begin_annotated_group(
                _tree_node_label(hierarchy.ids, idx, row)
            )
        target.fill_circle_aa(
            px, py, Float64(round_to_int(sc.point_radius)), color
        )
        if tooltips_on:
            target.end_annotated_group()
        text_requests.append(
            _TextRequest(
                round_to_int(px),
                round_to_int(py)
                + sc.tick_length
                + sc.label_gap
                + Int(sc.font_size),
                hierarchy.ids[row],
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    if show_legend:
        _draw_legend_at(
            target,
            text_requests,
            legend_labels,
            palette,
            legend,
            plot_x0,
            plot_y0,
            plot_x1,
            plot_y1,
            theme,
            cache=cache,
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def tree(
    df: DataFrame,
    ids: String,
    parent_ids: String,
    values: String,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Chart[Tree]:
    """`tree()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        ids: The string column for this channel.
        parent_ids: The string column for this channel.
        values: The numeric column for this channel.
        theme: See the list overload.
        width: See the list overload.
        height: See the list overload.
        title: See the list overload.
        subtitle: See the list overload.
        x_title: See the list overload.
        y_title: See the list overload.

    Returns:
        The finished chart -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var ids_values = _frame_strings(
        df, ids, "tree()", theme.missing, theme.missing_category_label
    )
    var parent_ids_values = _frame_strings(
        df, parent_ids, "tree()", theme.missing, theme.missing_category_label
    )
    var values_values = _frame_floats(df, values, "tree()", theme.missing)
    return tree(
        ids=ids_values,
        parent_ids=parent_ids_values,
        values=values_values,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )


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
) raises -> Chart[Tree]:
    """A tree diagram: a hierarchy drawn as connected nodes from a root,
    for showing structure and relationships (an org chart, a file tree, a
    decision tree) rather than each node's value, which a treemap or
    sunburst would emphasize instead.

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
        The finished chart -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import tree
        from dataviz import save

        def main() raises:
            var ids: List[String] = [
                "CEO", "Product", "Engineering", "Go-to-Market", "Operations",
                "Design", "Research", "Platform", "Applications",
                "Sales", "Success", "Finance", "People",
            ]
            var parent_ids: List[String] = [
                "", "CEO", "CEO", "CEO", "CEO",
                "Product", "Product", "Engineering", "Engineering",
                "Go-to-Market", "Go-to-Market",
                "Operations", "Operations",
            ]
            # Tree layout uses the relationships; unit leaf values keep each
            # team at equal visual weight.
            var values: List[Int] = [
                0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1,
            ]

            var c = tree(
                ids, parent_ids, values, title="Illustrative Company Organization"
            )
            save(c, "docs/src/examples/out_tree.svg")
        ```
    """
    var values_f = _materialize_scalar_list(values)
    var plot = (
        Plot()
        .mark_tree()
        .encode_hierarchy(ids=ids, parent_ids=parent_ids, values=values_f)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
