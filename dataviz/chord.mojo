from std.math import cos, pi, sin

from canvas.color import Color
from canvas.fill_rule import FillRule
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget
from dataviz.plot import _LazyFontCache

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
    _finished,
)
from dataviz.edges import _edge_node_index, _validate_edge_encoding
from dataviz.theme import Theme


def _draw_chord_ribbon[
    T: DrawTarget
](
    mut target: T,
    cx: Float64,
    cy: Float64,
    r: Float64,
    a0: Float64,
    a1: Float64,
    b0: Float64,
    b1: Float64,
    color: Color,
) raises:
    """One ribbon: a filled shape bounded by two node-rim arcs (`a0`->`a1`
    at node A, `b0`->`b1` at node B, both at inner radius `r`) and two
    curved connections between them. Each rim arc is a `Path.arc_to`
    segment (`canvas`'s center/radius/angle convention matches the
    `cos`/`sin` rim-point math here, and `SvgCanvas` emits a true arc
    command for it); each connection is a single `quad_curve_to` with its
    control point at the circle's center `(cx, cy)`, which bows every
    ribbon inward. `a0 <= a1`/`b0 <= b1` always hold, since
    `_render_chord`'s angles only advance forward, matching `arc_to`'s
    expectation.

    Filled `NONZERO` (#256). Both connections bow through the circle's
    center, so a ribbon between two nearly-opposite nodes can pinch to a
    point there and cross itself. Even-odd would read that overlap as
    outside and punch a hole in the middle of the ribbon; nonzero fills
    it solid, which is what a ribbon is meant to look like.
    """
    var path = Path()
    path.move_to(cx + r * cos(a0), cy + r * sin(a0))
    path.arc_to(cx, cy, r, a0, a1)
    path.quad_curve_to(cx, cy, cx + r * cos(b0), cy + r * sin(b0))
    path.arc_to(cx, cy, r, b0, b1)
    path.quad_curve_to(cx, cy, cx + r * cos(a0), cy + r * sin(a0))
    path.close()
    target.fill_path_aa(path, color, fill_rule=FillRule.NONZERO)


def _render_chord[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: _LazyFontCache,
) raises -> _RenderResult:
    """Render a `Mark.CHORD` plot: one node per distinct category across
    `encode_chord()`'s `from`/`to` columns (first-seen order, see
    `_edge_node_index`), arranged as ring sectors around a circle
    (starting at 12 o'clock, clockwise) sized by each node's total flow
    (every value where it is the `from` or the `to`), then one ribbon per
    row connecting a sub-arc of its `from` node to a sub-arc of its `to`
    node, each sub-arc sized `value / grand_total` of the full circle
    (`_draw_chord_ribbon`).

    Sub-arcs are allocated in row order, each advancing a per-node angular
    cursor (`node_cursor`, starting at the node's `node_start`). A
    self-loop allocates two sub-arcs off the same node in sequence.

    Ribbons take their `from` node's palette color
    (`default_categorical_palette()` by node position), reading as flow
    leaving that node. Ring thickness is
    `plot._mark_style.chord_ring_fraction` of the radius.
    """
    _validate_edge_encoding(plot, "Mark.CHORD")

    var theme = plot._theme
    var edges = _edge_node_index(
        plot._edges.from_categories, plot._edges.to_categories
    )
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
    var legend_reserve = _dynamic_legend_width(
        nodes, sc.legend_swatch_size, sc, cache=cache
    ) if show_legend else 0

    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    var inner_radius = radius * (1.0 - plot._mark_style.chord_ring_fraction)

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
        _draw_chord_ribbon(
            target,
            cx,
            cy,
            inner_radius,
            f0,
            f1,
            t0,
            t1,
            palette[fi % len(palette)],
        )

    for i in range(n):
        target.fill_ring_sector_aa(
            cx,
            cy,
            inner_radius,
            radius,
            node_start[i],
            node_end[i],
            palette[i % len(palette)],
        )

    var text_requests = List[_TextRequest]()
    if show_legend:
        _draw_legend(
            target,
            text_requests,
            nodes,
            palette,
            plot_x1 + sc.margin_right,
            plot_y0,
            theme,
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def chord(
    from_categories: List[String],
    to_categories: List[String],
    values: List[Float64],
    ring_fraction: Float64 = 0.08,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A chord diagram: nodes arranged around a circle with arcs between
    them sized by connection strength, for visualizing many-to-many
    relationships (flows, correlations, co-occurrences) that would be
    harder to scan as a matrix of numbers.

    `Mark.CHORD`: ring sectors for every distinct node across
    `from_categories`/`to_categories`, connected by ribbons sized by
    `values`. See `Plot.encode_chord()` (plot.mojo) for the data shape.

    Args:
        from_categories: Each flow's source node, one entry per row.
        to_categories: Each flow's destination node, one entry per
            row (paired with `from_categories[i]`).
        values: Each flow's magnitude, sizing its ribbon; must be
            non-negative.
        ring_fraction: The node rim's thickness as a fraction of the circle
            radius; defaults to `0.08`.
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
    var plot = (
        Plot()
        .mark_chord(ring_fraction=ring_fraction)
        .encode_chord(
            from_categories=from_categories,
            to_categories=to_categories,
            values=values,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def chord[
    dtype: DType
](
    from_categories: List[String],
    to_categories: List[String],
    values: List[Scalar[dtype]],
    ring_fraction: Float64 = 0.08,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`chord()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return chord(
        from_categories,
        to_categories,
        _materialize_scalar_list(values),
        ring_fraction=ring_fraction,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
