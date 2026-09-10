from std.math import cos, pi, sin

from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import categorical_palette_for
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _min_max,
    _finished,
)
from dataviz.edges import _edge_node_index, _validate_edge_encoding
from dataviz.theme import Theme


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
    """Render an edge list with nodes fixed around a circle.

    Edges are straight, their width scales with value, and their color follows
    the source node. Self-loops are skipped and labels sit outside the circle.
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

    var node_x = List[Float64](capacity=n)
    var node_y = List[Float64](capacity=n)
    for i in range(n):
        var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
        node_x.append(cx + max_radius * cos(angle))
        node_y.append(cy + max_radius * sin(angle))

    var palette = categorical_palette_for(theme)
    var value_mm = _min_max(plot._edges.values)
    var max_value = value_mm.max

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
        target.draw_line_aa(
            node_x[from_idx],
            node_y[from_idx],
            node_x[to_idx],
            node_y[to_idx],
            color,
            width,
        )

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
        if c > 0.3:
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
    """A network graph: nodes connected by edges and laid out to minimize
    crossings, for visualizing relationships without the ordering
    constraints an arc diagram or chord diagram impose.

    `Mark.GRAPH`: `Mark.CHORD`'s edge list (`Plot.encode_chord()`) drawn
    as nodes evenly spaced around a circle, connected by straight lines.
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
    var plot = (
        Plot()
        .mark_graph()
        .encode_chord(
            from_categories=from_categories,
            to_categories=to_categories,
            values=values,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
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
) raises -> Plot:
    """`graph()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (continuous.mojo). Delegates to the concrete overload
    above.
    """
    return graph(
        from_categories,
        to_categories,
        _materialize_scalar_list(values),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
