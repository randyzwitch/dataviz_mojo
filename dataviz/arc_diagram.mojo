from std.math import pi

from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.path import Path
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.core.color_scale import categorical_palette_for
from dataviz.core.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _min_max,
    _finished,
)
from dataviz.edges import _edge_node_index, _validate_edge_encoding
from dataviz.core.theme import Theme


def _render_arc_diagram[
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
    """Render an edge list as labeled nodes joined by semicircular arcs.

    Nodes are evenly spaced on a baseline. Edge width scales with value;
    edge color follows the source node. Self-loops are skipped.
    """
    _validate_edge_encoding(plot, "Mark.ARC_DIAGRAM")

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
    var baseline = Float64(plot_y1)

    var node_x = List[Float64](capacity=n)
    for i in range(n):
        var frac = 0.5 if n <= 1 else Float64(i) / Float64(n - 1)
        node_x.append(Float64(plot_x0) + frac * Float64(plot_x1 - plot_x0))

    var palette = categorical_palette_for(theme)
    var value_mm = _min_max(plot._edges.values)
    var max_value = value_mm.max

    var text_requests = List[_TextRequest]()

    for row in range(len(plot._edges.from_categories)):
        var from_idx = edges.from_idx[row]
        var to_idx = edges.to_idx[row]
        if from_idx == to_idx:
            continue
        var left_x = min(node_x[from_idx], node_x[to_idx])
        var right_x = max(node_x[from_idx], node_x[to_idx])
        var cx = (left_x + right_x) / 2.0
        var radius = (right_x - left_x) / 2.0
        var frac = (
            plot._edges.values[row] / max_value if max_value > 0.0 else 0.0
        )
        var width = sc.line_width + sc.line_width * 2.0 * frac
        var color = palette[from_idx % len(palette)]

        var path = Path()
        path.move_to(left_x, baseline)
        path.arc_to(cx, baseline, radius, pi, 2.0 * pi)
        target.stroke_path_aa(path, color, width)

    for i in range(n):
        var color = palette[i % len(palette)]
        # Keep the node centered on the arc endpoint.
        var px = node_x[i]
        var py = baseline
        target.fill_circle_aa(
            px, py, Float64(round_to_int(sc.point_radius)), color
        )
        text_requests.append(
            _TextRequest(
                round_to_int(px),
                round_to_int(py)
                + sc.tick_length
                + sc.label_gap
                + Int(sc.font_size),
                nodes[i],
                theme.text_color,
                sc.font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def arc_diagram(
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
    """An arc diagram: relationships between nodes on a single line, each
    connection drawn as a semicircular arc instead of a matrix or a 2D
    network layout. Well suited to nodes with a natural order (a
    timeline, a script's cast list), where a force-directed graph layout
    would add clutter without adding information.

    `Mark.ARC_DIAGRAM`: `Mark.CHORD`'s edge list (`Plot.encode_chord()`)
    drawn as nodes on one line connected by semicircular arcs. See
    `_render_arc_diagram`.

    Args:
        from_categories: Each edge's source node, one entry per row.
        to_categories: Each edge's destination node, one entry per
            row (paired with `from_categories[i]`).
        values: Each edge's magnitude, sizing its arc; must be
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
        from dataviz import arc_diagram
        from dataviz import save

        def main() raises:
            # Illustrative calls between services during a checkout request.
            # Edge weights are average calls per minute at peak traffic.
            var caller: List[String] = [
                "Gateway", "Gateway", "Checkout", "Checkout", "Checkout",
                "Catalog", "Catalog", "Payments", "Orders", "Orders",
                "Identity", "Notifications",
            ]
            var dependency: List[String] = [
                "Identity", "Catalog", "Identity", "Catalog", "Payments",
                "Inventory", "Search", "Fraud", "Inventory", "Notifications",
                "Fraud", "Identity",
            ]
            var calls_per_minute: List[Float64] = [
                820.0, 760.0, 410.0, 395.0, 370.0, 640.0,
                510.0, 350.0, 330.0, 290.0, 180.0, 120.0,
            ]

            var c = arc_diagram(
                caller,
                dependency,
                calls_per_minute,
                title="Illustrative Checkout Service Dependencies",
            )
            save(c, "docs/src/examples/out_arc_diagram.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_arc_diagram()
        .encode_chord(
            from_categories=from_categories,
            to_categories=to_categories,
            values=values,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
