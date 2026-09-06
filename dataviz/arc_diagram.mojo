from std.math import pi

from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.path import Path
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.color_scale import default_categorical_palette
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
    """Render a `Mark.ARC_DIAGRAM` plot: `Mark.CHORD`'s edge list
    (`encode_chord()`'s `from`/`to`/`value`) drawn as nodes on one
    straight, evenly spaced line with edges as semicircular arcs bulging
    upward. ECharts.jl's "Arc Diagram", unrelated to this package's
    `Mark.ARC` (pie/donut wedges).

    Each node's x is `index / (n - 1)` of the way across the plot (a
    single node centers). Each arc is centered at the horizontal midpoint
    between its two nodes on the baseline (`plot_y1`), with radius half
    the distance between them, so far-apart nodes get tall arcs. Arcs are
    not scaled down to fit the plot height.

    Edge stroke width scales linearly with `value / max(values)`, from
    `line_width` up to 3x that. Edge and node color follow the edge's
    `from` node's palette color (`default_categorical_palette()` by
    first-seen node position). A self-loop draws nothing. Node names are
    labeled beneath each marker; no legend is drawn.
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

    var palette = default_categorical_palette()
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
        # The arcs above already spring from the exact node_x, so the
        # dot has to sit there too -- rounding it left the foot of every
        # arc up to half a pixel off the node it belongs to.
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
        from dataviz.plot import save

        def main() raises:
            var from_characters: List[String] = ["Alice", "Bob", "Alice", "Carol", "Dave"]
            var to_characters: List[String] = ["Bob", "Carol", "Carol", "Dave", "Eve"]
            var scenes_together: List[Float64] = [8.0, 5.0, 3.0, 6.0, 4.0]

            var c = arc_diagram(from_characters, to_characters, scenes_together)
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
