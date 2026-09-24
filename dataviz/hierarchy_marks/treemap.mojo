from canvas.text.font_cache import FontCache
from canvas.color import Color
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
)
from dataviz.core.mark import Mark
from dataviz.plot import Plot, _finished
from dataviz.core.render_result import _RenderResult
from dataviz.core.text import _Scaled, _TextRequest
from dataviz.core.legend import _LegendLayout, _draw_legend_at, _legend_layout
from dataviz.core.validate import _require_non_negative
from dataviz.core.scale import _format_fixed, _label_decimals
from dataviz.core.theme import Theme
from dataviz.hierarchy_marks.tree import _assign_branch_colors


def _treemap_leaf_label(
    ids: List[String], idx: _HierarchyIndex, node: Int
) -> String:
    """One leaf rect's hover text (#681): `"id: value"` -- a small rect's
    label is often elided for space, so this is sometimes the only way
    to read it."""
    return (
        ids[node]
        + ": "
        + _format_fixed(
            idx.subtree_value[node], _label_decimals(idx.subtree_value[node])
        )
    )


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
    tooltips_on: Bool,
    sc: _Scaled,
    mut text_requests: List[_TextRequest],
) raises:
    """Recursively divide a rectangle by child subtree values.

    Split axes alternate by depth. Cumulative rounding keeps sibling edges
    aligned; leaves use their top-level branch color and a centered label.
    """
    if len(idx.children[node]) == 0:
        var color = (
            palette[branch[node] % len(palette)] if branch[node]
            >= 0 else theme.mark_color
        )
        if tooltips_on:
            target.begin_annotated_group(_treemap_leaf_label(ids, idx, node))
        target.fill_rect(x0, y0, x1 - x0, y1 - y0, color)
        if tooltips_on:
            target.end_annotated_group()
        text_requests.append(
            _TextRequest(
                (x0 + x1) // 2,
                (y0 + y1) // 2 + Int(sc.font_size * 0.35),
                ids[node],
                theme.treemap_label_color,
                sc.font_size,
                TextAlign.CENTER,
                theme.font_family,
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
        var next_pos = origin + round_to_int(span * cum)
        if split_x:
            _draw_treemap_node(
                target,
                c,
                prev,
                y0,
                next_pos,
                y1,
                depth + 1,
                idx,
                ids,
                branch,
                palette,
                theme,
                tooltips_on,
                sc,
                text_requests,
            )
        else:
            _draw_treemap_node(
                target,
                c,
                x0,
                prev,
                x1,
                next_pos,
                depth + 1,
                idx,
                ids,
                branch,
                palette,
                theme,
                tooltips_on,
                sc,
                text_requests,
            )
        prev = next_pos


def _render_treemap[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a `Mark.TREEMAP` plot: `_build_hierarchy_index`'s `children`/
    `subtree_value` (hierarchy.mojo) laid out by `_draw_treemap_node`'s
    slice-and-dice recursion from the whole inner plot rect at the root,
    with one color per top-level branch as in `Mark.SUNBURST`.

    Every value must be non-negative and the root's subtree total
    positive, the same validation `Mark.SUNBURST` applies.
    """
    if len(plot._hierarchy.parent_ids) != len(plot._hierarchy.ids) or len(
        plot._hierarchy.values
    ) != len(plot._hierarchy.ids):
        raise Error(
            "Plot.encode_hierarchy(): ids, parent_ids, and values must all have"
            " the same length (got "
            + String(len(plot._hierarchy.ids))
            + " ids, "
            + String(len(plot._hierarchy.parent_ids))
            + " parent_ids, "
            + String(len(plot._hierarchy.values))
            + " values)"
        )

    var theme = plot._settings.theme
    _require_non_negative(plot._hierarchy.values, "Mark.TREEMAP")

    var idx = _build_hierarchy_index(
        plot._hierarchy.ids, plot._hierarchy.parent_ids, plot._hierarchy.values
    )
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
    var legend = _legend_layout(
        legend_labels, sc.legend_swatch_size, sc, theme, ox1 - ox0, cache=cache
    ) if show_legend else _LegendLayout()

    var plot_x0 = ox0 + sc.margin_left + legend.left
    var plot_y0 = oy0 + sc.margin_top + legend.top
    var plot_x1 = ox1 - sc.margin_right - legend.right
    var plot_y1 = oy1 - sc.margin_bottom - legend.bottom

    var palette = categorical_palette_for(theme)
    # Only leaves are titled; an inner node is covered by its children.
    var leaves = 0
    for kids in idx.children:
        if len(kids) == 0:
            leaves += 1
    _draw_treemap_node(
        target,
        idx.root,
        plot_x0,
        plot_y0,
        plot_x1,
        plot_y1,
        0,
        idx,
        plot._hierarchy.ids,
        branch,
        palette,
        theme,
        plot._settings.tooltips_on(leaves),
        sc,
        text_requests,
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


def treemap(
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
) raises -> Plot:
    """`treemap()` over named columns of a `dataframe_mojo`
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
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var ids_values = _frame_strings(
        df, ids, "treemap()", theme.missing, theme.missing_category_label
    )
    var parent_ids_values = _frame_strings(
        df, parent_ids, "treemap()", theme.missing, theme.missing_category_label
    )
    var values_values = _frame_floats(df, values, "treemap()", theme.missing)
    return treemap(
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
    """A treemap, Ben Shneiderman's format for visualizing hierarchical
    data as nested rectangles: each rectangle's area proportional to its
    value, for showing a hierarchy's structure and its values' relative
    sizes in a compact, space-filling layout.

    `Mark.TREEMAP`: a hierarchy (`Plot.encode_hierarchy()`'s flattened
    `ids`/`parent_ids`/`values`) laid out as nested, area-proportional
    rectangles via slice-and-dice. See `_draw_treemap_node`.

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
        from dataviz import save

        def main() raises:
            # The same illustrative portfolio used by the sunburst example:
            # annual revenue by product line ($M), grouped into divisions.
            var ids: List[String] = [
                "Portfolio", "Cloud", "Commerce", "Data",
                "Compute", "Storage", "Security",
                "Checkout", "Subscriptions", "Marketplace",
                "Warehouse", "Streaming", "Governance",
            ]
            var parent_ids: List[String] = [
                "", "Portfolio", "Portfolio", "Portfolio",
                "Cloud", "Cloud", "Cloud",
                "Commerce", "Commerce", "Commerce",
                "Data", "Data", "Data",
            ]
            var revenue: List[Int] = [
                0, 0, 0, 0, 48, 31, 24, 42, 28, 19, 36, 22, 14,
            ]

            var c = treemap(
                ids,
                parent_ids,
                revenue,
                title="Illustrative Product Portfolio Revenue ($M)",
            )
            save(c, "docs/src/examples/out_treemap.svg")
        ```
    """
    var values_f = _materialize_scalar_list(values)
    var plot = (
        Plot()
        .mark_treemap()
        .encode_hierarchy(ids=ids, parent_ids=parent_ids, values=values_f)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
