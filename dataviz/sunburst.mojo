from std.math import pi

from canvas.color import Color
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


def _fill_ring_sector[
    T: DrawTarget
](mut target: T, cx: Float64, cy: Float64, inner: Float64, outer: Float64, a0: Float64, a1: Float64, color: Color) raises:
    """A ring sector, or -- when `inner == 0.0` -- a real wedge (the
    innermost ring of a sunburst touches the center, so it isn't a
    true "ring" with a hole at all): `fill_arc_aa` for the wedge case,
    `fill_ring_sector_aa` once there's a real inner radius, the same
    pie-vs-donut split `Mark.ARC` uses.
    """
    if inner <= 0.0:
        target.fill_arc_aa(cx, cy, outer, a0, a1, color)
    else:
        target.fill_ring_sector_aa(cx, cy, inner, outer, a0, a1, color)


def _draw_sunburst_node[
    T: DrawTarget
](
    mut target: T,
    node: Int,
    start_angle: Float64,
    end_angle: Float64,
    idx: _HierarchyIndex,
    cx: Float64,
    cy: Float64,
    ring_width: Float64,
    color: Color,
) raises:
    """Draw `node`'s ring sector (`idx.depth[node]` picks the ring
    -- depth 1 is innermost, touching the center; the root itself,
    depth 0, is never passed in here at all, see `_render_sunburst`'s docstring for why), then recurse into its children,
    dividing `[start_angle, end_angle)` by each child's share of
    `node`'s subtree total -- `color` stays fixed through the
    whole recursion, so this is always called with one already-chosen
    top-level branch color, never re-picked partway down.
    """
    var depth = idx.depth[node]
    var inner = ring_width * Float64(depth - 1)
    var outer = ring_width * Float64(depth)
    _fill_ring_sector(target, cx, cy, inner, outer, start_angle, end_angle, color)

    var total = idx.subtree_value[node]
    if total <= 0.0:
        return
    var span = end_angle - start_angle
    var a = start_angle
    for c in idx.children[node]:
        var a_end = a + span * (idx.subtree_value[c] / total)
        _draw_sunburst_node(target, c, a, a_end, idx, cx, cy, ring_width, color)
        a = a_end


def _render_sunburst[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.SUNBURST` plot: `_build_hierarchy_index`'s `children`/`depth`/`subtree_value` (hierarchy.mojo), drawn as
    concentric ring sectors -- `Mark.ARC`'s `fill_ring_sector_aa`
    primitive, reused directly, one call per node.

    The root itself is never drawn (there's no ring at depth 0 -- a
    sunburst's center is either empty or, in some real
    implementations, a clickable "zoom out" button this package has no
    equivalent interaction model for) -- rendering starts from each of
    the root's direct children instead, each claiming an angular
    slice proportional to its share of the root's subtree total and a
    freshly chosen palette color (`default_categorical_palette()`,
    indexed by that child's position among its siblings -- the same
    palette `_draw_legend` colors its swatches from below) that then
    stays fixed through every
    one of its descendants -- so the whole ring stack under one
    top-level branch reads as one consistent color, the same "which
    branch does this belong to" legibility a real sunburst needs that
    a per-node color would lose.

    Every value must be non-negative, and the root's subtree total
    (the sum of every leaf) must be positive -- the same "raise,
    don't silently misrepresent" stance `Mark.ARC`'s validation
    takes for its share-of-a-whole data.
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

    _require_non_negative(plot._hierarchy.values, "Mark.SUNBURST")

    var idx = _build_hierarchy_index(plot._hierarchy.ids, plot._hierarchy.parent_ids, plot._hierarchy.values)
    if idx.subtree_value[idx.root] <= 0.0:
        raise Error(
            "Plot: Mark.SUNBURST requires at least one positive leaf value"
            " (root's subtree total was "
            + String(idx.subtree_value[idx.root])
            + ")"
        )

    var text_requests = List[_TextRequest]()
    var root_children = idx.children[idx.root].copy()
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
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    var ring_width = max_radius / Float64(max(idx.max_depth, 1))

    var palette = default_categorical_palette()
    var root_total = idx.subtree_value[idx.root]
    var start = -pi / 2.0
    for i in range(len(root_children)):
        var c = root_children[i]
        var end = start + 2.0 * pi * (idx.subtree_value[c] / root_total)
        _draw_sunburst_node(target, c, start, end, idx, cx, cy, ring_width, palette[i % len(palette)])
        start = end

    if show_legend:
        _draw_legend(target, text_requests, legend_labels, palette, plot_x1 + sc.margin_right, plot_y0, theme)

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def sunburst(
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
    """A sunburst chart -- `Mark.SUNBURST`, a hierarchy (`Plot.encode_
    hierarchy()`'s flattened `ids`/`parent_ids`/`values`) drawn as
    concentric ring sectors, one ring per depth level. See `_render_
    sunburst`'s docstring for the full reasoning.

    Args:
        ids: Every node's unique id, flattened (not nested), one
            entry per node.
        parent_ids: Each node's parent id (must be a value present in
            `ids`, or empty for a root); paired with `ids[i]`.
        values: Each leaf node's size; an internal node's size is the
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
        from dataviz import sunburst
        from dataviz.plot import save

        def main() raises:
            var ids: List[String] = ["root", "src", "docs", "main.py", "utils.py", "guide.md", "api.md"]
            var parent_ids: List[String] = ["", "root", "root", "src", "src", "docs", "docs"]
            var sizes: List[Int] = [0, 0, 0, 45, 20, 12, 8]

            var c = sunburst(ids, parent_ids, sizes)
            save(c, "docs/src/examples/out_sunburst.svg")
        ```
    """
    var plot = Plot().mark_sunburst().encode_hierarchy(ids=ids, parent_ids=parent_ids, values=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def sunburst[
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
    """`sunburst()`, generalized over numeric element type -- see
    `scatter()`'s own `DType`-generic overload (plot.mojo) for the
    full reasoning. Delegates to the concrete `sunburst()` above.
    """
    return sunburst(
        ids, parent_ids, _materialize_scalar_list(values), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
