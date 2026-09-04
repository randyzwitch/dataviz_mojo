from canvas.fill_rule import FillRule
from canvas.geometry import _round_to_int
from canvas.path import Path
from canvas.text.render import TextAlign
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
    _finished,
)
from dataviz.edges import _edge_node_index, _validate_edge_encoding
from dataviz.theme import Theme


def _render_sankey[
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
    """Render a `Mark.SANKEY` plot: `encode_chord()`'s edge list laid out
    left-to-right by column. A node's column is the length of the longest
    path reaching it from any source, from one Kahn's-algorithm pass; a
    cycle raises.

    Each node is a vertical bar (`plot._mark_style.sankey_node_width`,
    scaled) whose height is proportional to `max(total inflow, total
    outflow)`, so an imbalance shows as a gap on the smaller side. Nodes
    in a column stack top-to-bottom by their share of the column total,
    with boundaries rounded cumulatively.

    Each flow is one or more straight-edged quadrilaterals between a
    slice of its `from` node's right edge and a slice of its `to` node's
    left edge. A skip edge (spanning more than one column) is spliced
    into a chain through one invisible pass-through node per
    intermediate column; pass-through nodes take vertical space like real
    nodes, every segment colors by the flow's original source, and there
    is no lane bundling. Flows in or out of one node stack in row order.
    A self-loop is dropped before layout. Every value must be
    non-negative.
    """
    _validate_edge_encoding(plot, "Mark.SANKEY")

    var theme = plot._theme
    var edges = _edge_node_index(
        plot._edges.from_categories, plot._edges.to_categories
    )
    ref nodes = edges.nodes
    var n = len(nodes)

    # A separate filtered pass rather than `edges.from_idx`/`to_idx`
    # directly: self-loops are dropped, so these columns are a subset of
    # the edge rows.
    var from_idx = List[Int](capacity=len(plot._edges.from_categories))
    var to_idx = List[Int](capacity=len(plot._edges.from_categories))
    var edge_value = List[Float64](capacity=len(plot._edges.from_categories))
    var children = List[List[Int]]()
    var in_degree = List[Int]()
    for _ in range(n):
        children.append(List[Int]())
        in_degree.append(0)
    for row in range(len(plot._edges.from_categories)):
        var fi = edges.from_idx[row]
        var ti = edges.to_idx[row]
        if fi == ti:
            continue
        from_idx.append(fi)
        to_idx.append(ti)
        edge_value.append(plot._edges.values[row])
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
            "Plot: Mark.SANKEY requires the edges to form a DAG (a cycle was"
            " found -- every real Sankey diagram's flow data must have no"
            " cycles)"
        )

    var max_column = 0
    for c in column:
        if c > max_column:
            max_column = c

    # Splice every skip edge (target column more than one past source
    # column) into a chain through one pass-through node per intermediate
    # column. `all_column` extends `column` with one entry per pass-through
    # node (indices `n..n_total-1`); `edge_origin` records each segment's
    # original source node for coloring.
    var final_from = List[Int]()
    var final_to = List[Int]()
    var final_value = List[Float64]()
    var edge_origin = List[Int]()
    var all_column = column.copy()
    for e in range(len(from_idx)):
        var fi = from_idx[e]
        var ti = to_idx[e]
        var gap = column[ti] - column[fi]
        if gap <= 1:
            final_from.append(fi)
            final_to.append(ti)
            final_value.append(edge_value[e])
            edge_origin.append(fi)
        else:
            var prev = fi
            for step in range(1, gap):
                var dummy_idx = len(all_column)
                all_column.append(column[fi] + step)
                final_from.append(prev)
                final_to.append(dummy_idx)
                final_value.append(edge_value[e])
                edge_origin.append(fi)
                prev = dummy_idx
            final_from.append(prev)
            final_to.append(ti)
            final_value.append(edge_value[e])
            edge_origin.append(fi)
    var n_total = len(all_column)

    var total_in = List[Float64](capacity=n_total)
    var total_out = List[Float64](capacity=n_total)
    for _ in range(n_total):
        total_in.append(0.0)
        total_out.append(0.0)
    for e in range(len(final_from)):
        total_out[final_from[e]] += final_value[e]
        total_in[final_to[e]] += final_value[e]
    var node_value = List[Float64](capacity=n_total)
    for i in range(n_total):
        node_value.append(max(total_in[i], total_out[i]))

    var sc = _Scaled(theme)
    var node_width = plot._mark_style.sankey_node_width * sc.scale
    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom

    var col_x = List[Float64](capacity=max_column + 1)
    for c in range(max_column + 1):
        var frac = 0.5 if max_column == 0 else Float64(c) / Float64(max_column)
        col_x.append(
            Float64(plot_x0)
            + frac * Float64(plot_x1 - plot_x0 - Int(node_width))
        )

    var nodes_in_column = List[List[Int]]()
    for _ in range(max_column + 1):
        nodes_in_column.append(List[Int]())
    for i in range(n_total):
        nodes_in_column[all_column[i]].append(i)

    var node_y0 = List[Float64](capacity=n_total)
    var node_y1 = List[Float64](capacity=n_total)
    for _ in range(n_total):
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
            node_y0[i] = Float64(plot_y0) + cum / col_total * Float64(
                plot_y1 - plot_y0
            )
            cum += node_value[i]
            node_y1[i] = Float64(plot_y0) + cum / col_total * Float64(
                plot_y1 - plot_y0
            )

    var palette = default_categorical_palette()
    var out_cursor = node_y0.copy()
    var in_cursor = node_y0.copy()
    for e in range(len(final_from)):
        var fi = final_from[e]
        var ti = final_to[e]
        var src_h = (final_value[e] / node_value[fi]) * (
            node_y1[fi] - node_y0[fi]
        ) if node_value[fi] > 0.0 else 0.0
        var src_top = out_cursor[fi]
        var src_bottom = src_top + src_h
        out_cursor[fi] = src_bottom

        var tgt_h = (final_value[e] / node_value[ti]) * (
            node_y1[ti] - node_y0[ti]
        ) if node_value[ti] > 0.0 else 0.0
        var tgt_top = in_cursor[ti]
        var tgt_bottom = tgt_top + tgt_h
        in_cursor[ti] = tgt_bottom

        var src_x = col_x[all_column[fi]] + node_width
        var tgt_x = col_x[all_column[ti]]

        var path = Path()
        path.move_to(src_x, src_top)
        path.line_to(src_x, src_bottom)
        path.line_to(tgt_x, tgt_bottom)
        path.line_to(tgt_x, tgt_top)
        path.close()
        target.fill_path_aa(
            path,
            palette[edge_origin[e] % len(palette)],
            fill_rule=FillRule.NONZERO,
        )

    var text_requests = List[_TextRequest]()
    for i in range(n):
        var x = _round_to_int(col_x[column[i]])
        var y0 = _round_to_int(node_y0[i])
        var h = max(1, _round_to_int(node_y1[i]) - y0)
        target.fill_rect(
            x, y0, _round_to_int(node_width), h, palette[i % len(palette)]
        )
        var label_x = x + _round_to_int(node_width) + sc.label_gap
        var label_y = y0 + h // 2 + Int(sc.font_size * 0.35)
        text_requests.append(
            _TextRequest(
                label_x,
                label_y,
                nodes[i],
                theme.text_color,
                sc.font_size,
                TextAlign.LEFT,
                theme.font_family,
            )
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def sankey(
    from_categories: List[String],
    to_categories: List[String],
    values: List[Float64],
    node_width: Float64 = 12.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A Sankey diagram, named after Irish engineer Matthew Sankey's 1898
    diagram of a steam engine's energy losses: nodes connected by flows
    whose width is proportional to quantity, for tracing how a total
    splits and moves through stages, such as energy, budget, or
    user-funnel flows.

    `Mark.SANKEY`: `Mark.CHORD`'s edge list (`Plot.encode_chord()`) drawn
    as nodes in left-to-right columns connected by proportionally sized
    flow ribbons. The edges must form a DAG. See `_render_sankey`.

    Args:
        from_categories: Each flow's source node, one entry per row.
            Together with `to_categories` the edges must form a DAG.
        to_categories: Each flow's destination node, one entry per
            row (paired with `from_categories[i]`).
        values: Each flow's magnitude, sizing its ribbon; must be
            non-negative.
        node_width: Each node bar's pixel width before `Theme.scale`; defaults
            to `12.0`.
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
        from dataviz import sankey
        from dataviz.plot import save

        def main() raises:
            var from_stage: List[String] = ["Coal", "Gas", "Coal", "Gas", "Electricity", "Electricity"]
            var to_stage: List[String] = ["Electricity", "Electricity", "Industry", "Industry", "Residential", "Industry"]
            var energy: List[Int] = [30, 20, 15, 10, 25, 20]

            var c = sankey(from_stage, to_stage, energy)
            save(c, "docs/src/examples/out_sankey.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_sankey(node_width=node_width)
        .encode_chord(
            from_categories=from_categories,
            to_categories=to_categories,
            values=values,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def sankey[
    dtype: DType
](
    from_categories: List[String],
    to_categories: List[String],
    values: List[Scalar[dtype]],
    node_width: Float64 = 12.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`sankey()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return sankey(
        from_categories,
        to_categories,
        _materialize_scalar_list(values),
        node_width=node_width,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
