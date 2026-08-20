from std.math import cos, pi, sin

from canvas_mojo.color import Color
from canvas_mojo.path import Path
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


def _fill_ring_sector[
    T: DrawTarget
](mut target: T, cx: Float64, cy: Float64, inner: Float64, outer: Float64, a0: Float64, a1: Float64, color: Color) raises:
    """A ring sector filled via a real `Path` (outer arc forward,
    straight edge in, inner arc backward, close) and `fill_path_aa`,
    *not* `DrawTarget.fill_ring_sector_aa` directly -- a real,
    confirmed bug in that primitive's own raster implementation
    (canvas_mojo's `_arc_bounds`, the bounding-box shortcut it scans
    only within): its own docstring claims "the inner arc's own bounds
    are always a subset of the outer arc's," which is false for a
    wedge that doesn't cross a cardinal angle (0/pi/2/pi/3pi/2) --
    the *straight radial edge* connecting the two arcs at the wedge's
    own end angle can reach a coordinate more extreme than anything on
    the outer arc itself (confirmed by hand: for a wedge from -pi/2 to
    -pi/6, the inner arc's own end point has a *larger* y than the
    outer arc's own computed max_y, since the two arcs' y-values move
    in opposite directions relative to center along that edge). The
    raster scan then never visits the pixels between the outer arc's
    own (too-small) computed bound and the wedge's own true extent,
    leaving them background -- a rectangular notch, not a clean
    angular gap, exactly what a two-branch sunburst rendered and
    looked at (not just pixel-asserted) showed before this fix. The
    SVG backend has no such bug (`SvgCanvas.fill_ring_sector_aa` emits
    real arc/line path commands with no bounding-box shortcut at all,
    confirmed by comparing its own output against this exact case),
    which is why only the raster path needed a workaround.

    `Path.arc_to`'s own docstring says `start_angle <= end_angle`
    "expected," but empirically traces a correct backward arc when
    given the reverse order too (confirmed directly against a real
    render before relying on it here, the same discipline this
    package always uses for an assumption about someone else's code)
    -- used for the inner arc's own return sweep, `a1` to `a0`.
    `inner == 0.0` (a real wedge, not a ring) works fine through this
    same path construction too, degenerating to a single point rather
    than a zero-length arc.
    """
    var path = Path()
    path.move_to(cx + outer * cos(a0), cy + outer * sin(a0))
    path.arc_to(cx, cy, outer, a0, a1)
    path.line_to(cx + inner * cos(a1), cy + inner * sin(a1))
    path.arc_to(cx, cy, inner, a1, a0)
    path.close()
    target.fill_path_aa(path, color)


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
    """Draw `node`'s own ring sector (`idx.depth[node]` picks the ring
    -- depth 1 is innermost, touching the center; the root itself,
    depth 0, is never passed in here at all, see `_render_sunburst`'s
    own docstring for why), then recurse into its own children,
    dividing `[start_angle, end_angle)` by each child's own share of
    `node`'s own subtree total -- `color` stays fixed through the
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
    """Render a `Mark.SUNBURST` plot: `_build_hierarchy_index`'s own
    `children`/`depth`/`subtree_value` (hierarchy.mojo), drawn as
    concentric ring sectors -- `Mark.ARC`'s own `fill_ring_sector_aa`
    primitive, reused directly, one call per node.

    The root itself is never drawn (there's no ring at depth 0 -- a
    sunburst's own center is either empty or, in some real
    implementations, a clickable "zoom out" button this package has no
    equivalent interaction model for) -- rendering starts from each of
    the root's own direct children instead, each claiming an angular
    slice proportional to its own share of the *root's* own subtree
    total and a freshly chosen palette color (`_draw_legend`'s own
    `default_categorical_palette()`, indexed by that child's own
    position among its siblings) that then stays fixed through every
    one of its own descendants -- so the whole ring stack under one
    top-level branch reads as one consistent color, the same "which
    branch does this belong to" legibility a real sunburst needs that
    a per-node color would lose.

    Every value must be non-negative, and the root's own subtree total
    (the sum of every leaf) must be positive -- the same "raise,
    don't silently misrepresent" stance `Mark.ARC`'s own validation
    already takes for its own share-of-a-whole data.
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
            raise Error("Plot: Mark.SUNBURST values must be non-negative (got " + String(v) + ")")

    var idx = _build_hierarchy_index(plot._hierarchy_ids, plot._hierarchy_parent_ids, plot._hierarchy_values)
    if idx.subtree_value[idx.root] <= 0.0:
        raise Error(
            "Plot: Mark.SUNBURST requires at least one positive leaf value"
            " (root's own subtree total was "
            + String(idx.subtree_value[idx.root])
            + ")"
        )

    var text_requests = List[_TextRequest]()
    var root_children = idx.children[idx.root].copy()
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
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A sunburst chart -- `Mark.SUNBURST`, a hierarchy (`Plot.encode_
    hierarchy()`'s own flattened `ids`/`parent_ids`/`values`) drawn as
    concentric ring sectors, one ring per depth level. See `_render_
    sunburst`'s own docstring for the full reasoning."""
    var plot = Plot().mark_sunburst().encode_hierarchy(ids=ids, parent_ids=parent_ids, values=values)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
