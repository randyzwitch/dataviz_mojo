from std.math import cos, pi, sin, sqrt

from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats, _frame_strings
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.color_scale import categorical_palette_for
from dataviz.core.mark import Mark
from dataviz.plot import Plot, _finished
from dataviz.core.render_result import _RenderResult
from dataviz.core.tooltip_labels import _edge_tooltip_label
from dataviz.core.text import _Scaled, _TextRequest
from dataviz.core.scale import _min_max
from dataviz.relationships.edges import (
    GraphLayout,
    _edge_node_index,
    _validate_edge_encoding,
)
from dataviz.core.theme import Theme


def _force_layout(
    n: Int, from_idx: List[Int], to_idx: List[Int]
) -> Tuple[List[Float64], List[Float64]]:
    """Node positions in the unit square by a force-directed layout
    (#157), Fruchterman and Reingold's spring embedder.

    Every pair of nodes repels with force `k^2 / d` and every edge
    attracts its ends with `d^2 / k`, where `k = sqrt(1 / n)` is the
    ideal spacing; each step moves a node along its net force, by no
    more than a temperature that cools linearly to zero over 300 steps.
    A weak pull toward the center keeps disconnected pieces from
    drifting apart without bound.

    It starts from the circle `GraphLayout.CIRCLE` draws rather than
    from random positions, so the result is the same on every render
    with no seed to carry. Self-loops exert no force.
    """
    var xs = List[Float64](capacity=n)
    var ys = List[Float64](capacity=n)
    for i in range(n):
        var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
        xs.append(0.5 + 0.5 * cos(angle))
        ys.append(0.5 + 0.5 * sin(angle))
    if n < 2:
        return (xs^, ys^)
    var k = sqrt(1.0 / Float64(n))
    var steps = 300
    var t0 = 0.1
    for step in range(steps):
        var dx = List[Float64](capacity=n)
        var dy = List[Float64](capacity=n)
        for i in range(n):
            # Gravity toward the center, proportional to distance.
            dx.append((0.5 - xs[i]) * k)
            dy.append((0.5 - ys[i]) * k)
        for i in range(n):
            for j in range(i + 1, n):
                var ex = xs[i] - xs[j]
                var ey = ys[i] - ys[j]
                var d = max(sqrt(ex * ex + ey * ey), 1e-9)
                var f = k * k / d
                dx[i] += ex / d * f
                dy[i] += ey / d * f
                dx[j] -= ex / d * f
                dy[j] -= ey / d * f
        for e in range(len(from_idx)):
            var u = from_idx[e]
            var v = to_idx[e]
            if u == v:
                continue
            var ex = xs[u] - xs[v]
            var ey = ys[u] - ys[v]
            var d = max(sqrt(ex * ex + ey * ey), 1e-9)
            var f = d * d / k
            dx[u] -= ex / d * f
            dy[u] -= ey / d * f
            dx[v] += ex / d * f
            dy[v] += ey / d * f
        var temp = t0 * (1.0 - Float64(step) / Float64(steps))
        for i in range(n):
            var m = sqrt(dx[i] * dx[i] + dy[i] * dy[i])
            if m > 0.0:
                var move = min(m, temp)
                xs[i] += dx[i] / m * move
                ys[i] += dy[i] / m * move
    return (xs^, ys^)


def _render_graph[
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
    """Render an edge list as nodes joined by straight edges, placed
    around a circle or by `_force_layout` (`GraphLayout`, #157).

    Edges are straight, their width scales with value, and their color follows
    the source node. Self-loops are skipped. Around a circle the labels sit
    outside it; in a force layout, which has no outside, each sits centered
    under its node, and the layout is scaled to fill the plot area with room
    left for the labels below.
    """
    _validate_edge_encoding(plot, "Mark.GRAPH")

    var theme = plot._theme
    var edges = _edge_node_index(
        plot._edges.from_categories, plot._edges.to_categories
    )
    ref nodes = edges.nodes
    var n = len(nodes)

    var sc = _Scaled(theme)
    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = (
        Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    )

    var force = plot._mark_style.graph_layout == GraphLayout.FORCE
    var node_x = List[Float64](capacity=n)
    var node_y = List[Float64](capacity=n)
    if force:
        var unit = _force_layout(n, edges.from_idx, edges.to_idx)
        var lo_x = unit[0][0]
        var hi_x = unit[0][0]
        var lo_y = unit[1][0]
        var hi_y = unit[1][0]
        for i in range(n):
            lo_x = min(lo_x, unit[0][i])
            hi_x = max(hi_x, unit[0][i])
            lo_y = min(lo_y, unit[1][i])
            hi_y = max(hi_y, unit[1][i])
        # Inset by a node radius on every side, and by a label's height
        # more at the bottom, so neither is clipped by the frame.
        var pad = Float64(round_to_int(sc.point_radius)) + 1.0
        var fx0 = Float64(plot_x0) + pad
        var fx1 = Float64(plot_x1) - pad
        var fy0 = Float64(plot_y0) + pad
        var fy1 = Float64(plot_y1) - pad - Float64(sc.label_gap) - sc.font_size
        for i in range(n):
            var tx = 0.5 if hi_x == lo_x else (unit[0][i] - lo_x) / (
                hi_x - lo_x
            )
            var ty = 0.5 if hi_y == lo_y else (unit[1][i] - lo_y) / (
                hi_y - lo_y
            )
            node_x.append(fx0 + (fx1 - fx0) * tx)
            node_y.append(fy0 + (fy1 - fy0) * ty)
    else:
        for i in range(n):
            var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
            node_x.append(cx + max_radius * cos(angle))
            node_y.append(cy + max_radius * sin(angle))

    var palette = categorical_palette_for(theme)
    var value_mm = _min_max(plot._edges.values)
    var max_value = value_mm.max

    var tooltips_on = plot._tooltips_on(len(plot._edges.from_categories))
    for row in range(len(plot._edges.from_categories)):
        var from_idx = edges.from_idx[row]
        var to_idx = edges.to_idx[row]
        if from_idx == to_idx:
            continue
        var frac = (
            plot._edges.values[row] / max_value if max_value > 0.0 else 0.0
        )
        var width = sc.line_width + sc.line_width * 2.0 * frac
        var color = palette[from_idx % len(palette)]
        # Preserve exact node endpoints for diagonal edges.
        if tooltips_on:
            target.begin_annotated_group(
                _edge_tooltip_label(
                    plot._edges.from_categories[row],
                    plot._edges.to_categories[row],
                    plot._edges.values[row],
                )
            )
        target.draw_line_aa(
            node_x[from_idx],
            node_y[from_idx],
            node_x[to_idx],
            node_y[to_idx],
            color,
            width,
        )
        if tooltips_on:
            target.end_annotated_group()

    var text_requests = List[_TextRequest]()
    for i in range(n):
        var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
        var color = palette[i % len(palette)]
        # The node sits exactly where the ring put it, so the edges
        # meeting it land on its center. The radius still rounds: it is
        # one constant for the whole chart, which is what every other
        # mark drawing Theme.point_radius does.
        var px = node_x[i]
        var py = node_y[i]
        target.fill_circle_aa(
            px, py, Float64(round_to_int(sc.point_radius)), color
        )

        var label_x = cx + (max_radius + Float64(sc.label_gap)) * cos(angle)
        var label_y = cy + (max_radius + Float64(sc.label_gap)) * sin(angle)
        var c = cos(angle)
        var align = TextAlign.CENTER
        if force:
            label_x = px
            label_y = (
                py
                + Float64(round_to_int(sc.point_radius) + sc.label_gap)
                + sc.font_size * 0.65
            )
        elif c > 0.3:
            align = TextAlign.LEFT
        elif c < -0.3:
            align = TextAlign.RIGHT
        text_requests.append(
            _TextRequest(
                round_to_int(label_x),
                round_to_int(label_y) + Int(sc.font_size * 0.35),
                nodes[i],
                theme.text_color,
                sc.font_size,
                align,
                theme.font_family,
            )
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def graph(
    df: DataFrame,
    from_categories: String,
    to_categories: String,
    values: String,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    layout: GraphLayout = GraphLayout.CIRCLE,
) raises -> Plot:
    """`graph()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        from_categories: The string column for this channel.
        to_categories: The string column for this channel.
        values: The numeric column for this channel.
        theme: See the list overload.
        width: See the list overload.
        height: See the list overload.
        title: See the list overload.
        subtitle: See the list overload.
        x_title: See the list overload.
        y_title: See the list overload.
        layout: See the list overload.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var from_categories_values = _frame_strings(
        df,
        from_categories,
        "graph()",
        theme.missing,
        theme.missing_category_label,
    )
    var to_categories_values = _frame_strings(
        df,
        to_categories,
        "graph()",
        theme.missing,
        theme.missing_category_label,
    )
    var values_values = _frame_floats(df, values, "graph()", theme.missing)
    return graph(
        from_categories=from_categories_values,
        to_categories=to_categories_values,
        values=values_values,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
        layout=layout,
    )


def graph[
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
    layout: GraphLayout = GraphLayout.CIRCLE,
) raises -> Plot:
    """A network graph: nodes connected by edges, for visualizing
    relationships without the ordering constraints an arc diagram or
    chord diagram impose.

    `Mark.GRAPH`: `Mark.CHORD`'s edge list (`Plot.encode_chord()`) drawn
    as nodes joined by straight lines -- evenly spaced around a circle
    by default, or with `layout=GraphLayout.FORCE` placed by a
    force-directed layout that gathers connected nodes together (#157).
    See `_render_graph`.

    Args:
        from_categories: Each edge's source node, one entry per row.
        to_categories: Each edge's destination node, one entry per
            row (paired with `from_categories[i]`).
        values: Each edge's magnitude, sizing its connecting line;
            must be non-negative.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.
        layout: Where the nodes go: `GraphLayout.CIRCLE` (the default)
            or `GraphLayout.FORCE`.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import graph
        from dataviz import save

        def main() raises:
            # Illustrative weekly pallet movements through a distribution network.
            var origin: List[String] = [
                "North Plant", "South Plant", "North Plant", "South Plant",
                "Central Hub", "Central Hub", "Coastal Hub", "Coastal Hub",
                "Metro DC", "Metro DC", "Regional DC", "Regional DC",
            ]
            var destination: List[String] = [
                "Central Hub", "Central Hub", "Coastal Hub", "Coastal Hub",
                "Metro DC", "Regional DC", "Metro DC", "Port DC",
                "City Stores", "Airport Stores", "Town Stores", "Rural Stores",
            ]
            var pallets: List[Int] = [
                420, 360, 190, 240, 310, 270, 225, 180, 205, 95, 175, 120,
            ]

            var c = graph(
                origin,
                destination,
                pallets,
                title="Illustrative Weekly Distribution Network",
            )
            save(c, "docs/src/examples/out_graph.svg")
        ```
    """
    var values_f = _materialize_scalar_list(values)
    var plot = (
        Plot()
        .mark_graph(layout=layout)
        .encode_chord(
            from_categories=from_categories,
            to_categories=to_categories,
            values=values_f,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
