from canvas_mojo.color import Color
from canvas_mojo.geometry import _round_to_int
from canvas_mojo.text.render import TextAlign
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.hierarchy import _HierarchyIndex, _build_hierarchy_index
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_legend,
    _dynamic_legend_width,
    _empty_result,
    _rendered,
)
from dataviz_mojo.theme import Theme
from dataviz_mojo.tree import _assign_branch_colors

comptime _TREEMAP_LABEL_COLOR = Color(255, 255, 255)
"""Every leaf's own label draws in plain white, not `Theme.text_color`
-- the one label in this whole package drawn *over* a solid fill
rather than over the background, so `text_color`'s own default (a
near-black, chosen to read against `Theme.background`) would be
exactly the wrong contrast direction here. Fixed, not a new `Theme`
field, the same "no concrete need for a knob yet" reasoning every
other fixed layout/color constant in this package already follows."""


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
    """Fill `node`'s own rect `(x0, y0, x1, y1)` if it's a leaf
    (colored by `branch[node]`'s own top-level-ancestor palette entry,
    the same convention `Mark.SUNBURST`/`TREE` already establish, plus
    a centered white label -- see `_TREEMAP_LABEL_COLOR`'s own
    docstring), otherwise slice-and-dice that rect among its own
    children and recurse: alternating axis by `depth` (even splits the
    *width*, into side-by-side vertical strips; odd splits the
    *height*, into stacked horizontal strips), each child's own share
    of the split proportional to its own `subtree_value` share of
    `node`'s own total -- the standard, simplest real treemap layout
    (*not* a real squarified algorithm, which additionally rebalances
    each slice's own aspect ratio toward square instead of letting a
    row of many small children go arbitrarily thin -- a real,
    documented v1 simplification, the same tolerance `Mark.TREE`'s own
    `_assign_leaf_positions` docstring already takes over a full
    Reingold-Tilford layout).

    Every boundary along the split axis comes from rounding a
    *cumulative* fraction of the rect's own span, never an
    independently-rounded width -- the same "round the boundaries, not
    the size" pattern `Mark.MARIMEKKO`'s own docstring already
    establishes (there for one level of columns; here for every level
    of the recursion), so adjacent siblings' own rects always share an
    exact pixel edge with no hairline gap.
    """
    if len(idx.children[node]) == 0:
        var color = palette[branch[node] % len(palette)] if branch[node] >= 0 else theme.mark_color
        target.fill_rect(x0, y0, x1 - x0, y1 - y0, color)
        text_requests.append(
            _TextRequest(
                (x0 + x1) // 2, (y0 + y1) // 2 + Int(sc.font_size * 0.35), ids[node], _TREEMAP_LABEL_COLOR,
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
    """Render a `Mark.TREEMAP` plot: `_build_hierarchy_index`'s own
    `children`/`subtree_value` (hierarchy.mojo), laid out via `_draw_
    treemap_node`'s own slice-and-dice recursion starting from the
    whole inner plot rect at the root. See that function's own
    docstring for the full layout reasoning, and `Mark.SUNBURST`'s own
    docstring for the shared "one color per top-level branch" idea
    reused here too.

    Every value must be non-negative, and the root's own subtree total
    must be positive -- the same validation `Mark.SUNBURST` already
    takes for the identical reason (a treemap's own leaf areas are a
    share-of-a-whole reading, same as a pie wedge's own angle).
    """
    if (
        len(plot._hierarchy_parent_ids) != len(plot._hierarchy_ids)
        or len(plot._hierarchy_values) != len(plot._hierarchy_ids)
    ):
        raise Error(
            "Plot.encode_hierarchy(): ids, parent_ids, and values must all have the"
            " same length (got "
            + String(len(plot._hierarchy_ids))
            + " ids, "
            + String(len(plot._hierarchy_parent_ids))
            + " parent_ids, "
            + String(len(plot._hierarchy_values))
            + " values)"
        )

    var theme = plot._theme
    if len(plot._hierarchy_ids) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    for v in plot._hierarchy_values:
        if v < 0.0:
            raise Error("Plot: Mark.TREEMAP values must be non-negative (got " + String(v) + ")")

    var idx = _build_hierarchy_index(plot._hierarchy_ids, plot._hierarchy_parent_ids, plot._hierarchy_values)
    if idx.subtree_value[idx.root] <= 0.0:
        raise Error(
            "Plot: Mark.TREEMAP requires at least one positive leaf value"
            " (root's own subtree total was "
            + String(idx.subtree_value[idx.root])
            + ")"
        )

    var n = len(plot._hierarchy_ids)
    var branch = List[Int](capacity=n)
    for _ in range(n):
        branch.append(-1)
    var root_children = idx.children[idx.root].copy()
    for i in range(len(root_children)):
        _assign_branch_colors(root_children[i], i, idx, branch)

    var text_requests = List[_TextRequest]()
    var legend_labels = List[String]()
    for c in root_children:
        legend_labels.append(plot._hierarchy_ids[c])

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _dynamic_legend_width(legend_labels, sc.legend_swatch_size, sc) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom

    var palette = default_categorical_palette()
    _draw_treemap_node(
        target, idx.root, plot_x0, plot_y0, plot_x1, plot_y1, 0, idx, plot._hierarchy_ids, branch, palette, theme,
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
) raises -> Canvas:
    """A treemap -- `Mark.TREEMAP`, a hierarchy (`Plot.encode_
    hierarchy()`'s own flattened `ids`/`parent_ids`/`values`) laid out
    as nested, area-proportional rectangles via slice-and-dice. See
    `_draw_treemap_node`'s own docstring for the full reasoning."""
    var plot = Plot().mark_treemap().encode_hierarchy(ids=ids, parent_ids=parent_ids, values=values)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
