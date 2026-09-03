from std.math import cos, pi, sin

from canvas.color import Color
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import default_categorical_palette
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
)
from dataviz.edges import _edge_node_index, _validate_edge_encoding
from dataviz.theme import Theme


def _draw_chord_ribbon[
    T: DrawTarget
](mut target: T, cx: Float64, cy: Float64, r: Float64, a0: Float64, a1: Float64, b0: Float64, b1: Float64, color: Color) raises:
    """One ribbon: a filled shape bounded by two node-rim arcs (`a0`
    ->`a1` at node A's inner radius, `b0`->`b1` at node B's) and
    two curved "cross" connections between them -- the classic chord-
    diagram ribbon shape. Each rim arc is a real `Path.arc_to` segment
    (`canvas`'s center/radius/angle convention matches this file's
    `cos`/`sin` rim-point math exactly, so no angle conversion is
    needed at the call site); each cross connection is a single
    `quad_curve_to` pulled toward the circle's center `(cx, cy)`, which
    bows every ribbon inward through the middle the way a real chord
    diagram's ribbons do, without needing per-ribbon control-point math
    of its own. `a0 <= a1`/`b0 <= b1` always hold here (`_render_
    chord`'s angles only ever advance forward around the circle),
    matching `arc_to`'s `start_angle <= end_angle` expectation.

    `arc_to` also means `SvgCanvas`'s path output emits a true
    elliptical-arc command for the rim instead of a polyline, so a
    chord diagram's vector output is a real curve, not a many-segment
    approximation of one.

    `r` is the *inner* radius of the node ring (`_render_chord`'s `inner_radius`) -- ribbons visually originate from just inside the
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
    across `encode_chord()`'s `from`/`to` columns (first-seen order
    across the two concatenated columns -- see `_edge_node_index`'s
    docstring), arranged
    as ring sectors around a circle (`Mark.ARC`'s start-at-12-
    o'clock, sweep-clockwise convention, reused exactly -- see `_render_
    arc`'s docstring) sized by each node's *total* flow (every
    value where it's the `from` or the `to`, so a node with several
    edges gets one contiguous arc, not several) -- then one ribbon per
    `from`/`to`/`value` row, connecting a sub-arc of its `from` node's ring to a sub-arc of its `to` node's, each sub-arc sized `value
    / node's total` of that node's full span (`_draw_chord_ribbon`).

    Sub-arcs are allocated in the order rows are given, each one
    advancing a per-node running angular cursor (`node_cursor`, starting
    at that node's `node_start`) -- the same running-total
    bookkeeping style `Mark.WATERFALL`'s `encode_waterfall` uses, just
    for angles instead of a bar's running total.
    A self-loop (`from[i] == to[i]`) allocates two sub-arcs off the
    same node in sequence rather than one -- not specifically tested,
    but not rejected either, since nothing here assumes `from[i] !=
    to[i]`.

    Ribbons are colored by their `from` node's palette color
    (`default_categorical_palette()`, the same index-by-node-position
    convention `Mark.ARC`'s wedge coloring uses) -- a ribbon reads
    as "flow leaving this node," not a third, edge-specific color.
    """
    _validate_edge_encoding(plot, "Mark.CHORD")

    var theme = plot._theme
    if len(plot._edges.from_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var edges = _edge_node_index(plot._edges.from_categories, plot._edges.to_categories)
    ref nodes = edges.nodes
    ref from_idx = edges.from_idx
    ref to_idx = edges.to_idx
    var n = len(nodes)

    var node_total = List[Float64]()
    for _ in range(n):
        node_total.append(0.0)
    for i in range(len(plot._edges.from_categories)):
        node_total[from_idx[i]] += plot._edges.values[i]
        node_total[to_idx[i]] += plot._edges.values[i]

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
    var inner_radius = radius * (1.0 - theme.chord_ring_fraction)

    var palette = default_categorical_palette()

    for i in range(len(plot._edges.from_categories)):
        var fi = from_idx[i]
        var ti = to_idx[i]
        var value = plot._edges.values[i]
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
) raises -> Plot:
    """A chord diagram -- `Mark.CHORD`, ring sectors for every distinct
    node across `from_categories`/`to_categories`, connected by ribbons
    sized by `values`. See `Plot.encode_chord()`'s docstring
    (plot.mojo) for the exact shape.

    Args:
        from_categories: Each flow's source node, one entry per row.
        to_categories: Each flow's destination node, one entry per
            row (paired with `from_categories[i]`).
        values: Each flow's magnitude, sizing its ribbon; must be
            non-negative.
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
        from dataviz import chord
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var from_regions: List[String] = ["North", "North", "South", "East", "West"]
            var to_regions: List[String] = ["South", "East", "West", "West", "North"]
            var trade_volume: List[Int] = [12, 8, 15, 6, 10]

            var c = chord(from_regions, to_regions, trade_volume)
            save(c, "docs/src/examples/out_chord.svg")
        ```
    """
    var plot = Plot().mark_chord().encode_chord(
        from_categories=from_categories, to_categories=to_categories, values=values
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def chord[
    dtype: DType
](
    from_categories: List[String],
    to_categories: List[String],
    values: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`chord()`, generalized over numeric element type -- see
    `scatter()`'s own `DType`-generic overload (plot.mojo) for the
    full reasoning. Delegates to the concrete `chord()` above.
    """
    return chord(
        from_categories, to_categories, _materialize_scalar_list(values), theme=theme, width=width,
        height=height, title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
