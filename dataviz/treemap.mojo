from canvas.color import Color
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
from dataviz.tree import _assign_branch_colors


def _draw_treemap_node[
    T: DrawTarget
](
    mut target: T,
    node: Int,
    x0: Int,
    y0: Int,
    x1: Int,
    y1: Int,
    depth: Int,
    idx: _HierarchyIndex,
    ids: List[String],
    branch: List[Int],
    palette: List[Color],
    theme: Theme,
    sc: _Scaled,
    mut text_requests: List[_TextRequest],
) raises:
    """Fill `node`'s rect `(x0, y0, x1, y1)` if it's a leaf
    (colored by `branch[node]`'s top-level-ancestor palette entry,
    the same convention `Mark.SUNBURST`/`TREE` use, plus
    a centered label in `Theme.treemap_label_color`), otherwise slice-and-dice that rect among its children and recurse: alternating axis by `depth` (even splits the
    *width*, into side-by-side vertical strips; odd splits the
    *height*, into stacked horizontal strips), each child's share
    of the split proportional to its `subtree_value` share of
    `node`'s total -- the standard, simplest real treemap layout
    (*not* a real squarified algorithm, which additionally rebalances
    each slice's aspect ratio toward square instead of letting a
    row of many small children go arbitrarily thin -- a real,
    documented simplification, the same tolerance `Mark.TREE`'s `_assign_leaf_positions` docstring takes over a full
    Reingold-Tilford layout).

    Every boundary along the split axis comes from rounding a
    *cumulative* fraction of the rect's span, never an
    independently-rounded width -- the same "round the boundaries, not
    the size" pattern `Mark.MARIMEKKO`'s docstring already
    establishes (there for one level of columns; here for every level
    of the recursion), so adjacent siblings' rects always share an
    exact pixel edge with no hairline gap.
    """
    if len(idx.children[node]) == 0:
        var color = palette[branch[node] % len(palette)] if branch[node] >= 0 else theme.mark_color
        target.fill_rect(x0, y0, x1 - x0, y1 - y0, color)
        text_requests.append(
            _TextRequest(
                (x0 + x1) // 2, (y0 + y1) // 2 + Int(sc.font_size * 0.35), ids[node], theme.treemap_label_color,
                sc.font_size, TextAlign.CENTER, theme.font_family,
            )
        )
        return

    var total = idx.subtree_value[node]
    if total <= 0.0:
        return

    var split_x = depth % 2 == 0
    var span = Float64(x1 - x0) if split_x else Float64(y1 - y0)
    var origin = x0 if split_x else y0
    var cum = 0.0
    var prev = origin
    for c in idx.children[node]:
        cum += idx.subtree_value[c] / total
        var next_pos = origin + _round_to_int(span * cum)
        if split_x:
            _draw_treemap_node(target, c, prev, y0, next_pos, y1, depth + 1, idx, ids, branch, palette, theme, sc, text_requests)
        else:
            _draw_treemap_node(target, c, x0, prev, x1, next_pos, depth + 1, idx, ids, branch, palette, theme, sc, text_requests)
        prev = next_pos


def _render_treemap[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.TREEMAP` plot: `_build_hierarchy_index`'s `children`/`subtree_value` (hierarchy.mojo), laid out via `_draw_
    treemap_node`'s slice-and-dice recursion starting from the
    whole inner plot rect at the root -- see that function's
    docstring for the full layout reasoning. Reuses `Mark.SUNBURST`'s
    "one color per top-level branch" idea.

    Every value must be non-negative, and the root's subtree total
    must be positive -- the same validation `Mark.SUNBURST` already
    takes for the identical reason (a treemap's leaf areas are a
    share-of-a-whole reading, same as a pie wedge's angle).
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

    _require_non_negative(plot._hierarchy.values, "Mark.TREEMAP")

    var idx = _build_hierarchy_index(plot._hierarchy.ids, plot._hierarchy.parent_ids, plot._hierarchy.values)
    if idx.subtree_value[idx.root] <= 0.0:
        raise Error(
            "Plot: Mark.TREEMAP requires at least one positive leaf value"
            " (root's subtree total was "
            + String(idx.subtree_value[idx.root])
            + ")"
        )

    var n = len(plot._hierarchy.ids)
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
    _draw_treemap_node(
        target, idx.root, plot_x0, plot_y0, plot_x1, plot_y1, 0, idx, plot._hierarchy.ids, branch, palette, theme,
        sc, text_requests,
    )

    if show_legend:
        _draw_legend(target, text_requests, legend_labels, palette, plot_x1 + sc.margin_right, plot_y0, theme)

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def treemap(
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
    """A treemap -- `Mark.TREEMAP`, a hierarchy (`Plot.encode_
    hierarchy()`'s flattened `ids`/`parent_ids`/`values`) laid out
    as nested, area-proportional rectangles via slice-and-dice. See
    `_draw_treemap_node`'s docstring for the full reasoning.

    Args:
        ids: Every node's unique id, flattened (not nested), one
            entry per node.
        parent_ids: Each node's parent id (must be a value present in
            `ids`, or empty for the single root); paired with
            `ids[i]`.
        values: Each leaf node's area; an internal node's area is the
            sum of its descendants' -- see `Plot.encode_hierarchy()`'s
            docstring for the exact rule.
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
        from dataviz import treemap
        from dataviz.plot import save

        def main() raises:
            var ids: List[String] = ["root", "src", "docs", "main.py", "utils.py", "guide.md", "api.md"]
            var parent_ids: List[String] = ["", "root", "root", "src", "src", "docs", "docs"]
            var sizes: List[Int] = [0, 0, 0, 45, 20, 12, 8]

            var c = treemap(ids, parent_ids, sizes)
            save(c, "docs/src/examples/out_treemap.svg")
        ```
    """
    var plot = Plot().mark_treemap().encode_hierarchy(ids=ids, parent_ids=parent_ids, values=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def treemap[
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
    """`treemap()`, generalized over numeric element type -- see
    `scatter()`'s own `DType`-generic overload (plot.mojo) for the
    full reasoning. Delegates to the concrete `treemap()` above.
    """
    return treemap(
        ids, parent_ids, _materialize_scalar_list(values), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
