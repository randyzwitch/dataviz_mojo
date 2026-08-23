from std.math import pi

from canvas_mojo.color import Color
from canvas_mojo.geometry import _round_to_int
from canvas_mojo.path import Path
from canvas_mojo.text.render import TextAlign
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.vector.svg import SvgCanvas
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _empty_result,
    _min_max,
    _rendered,
)
from dataviz_mojo.edges import _edge_node_index, _validate_edge_encoding
from dataviz_mojo.theme import Theme


def _render_arc_diagram[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.ARC_DIAGRAM` plot: `Mark.CHORD`'s own edge-list
    shape (`encode_chord()`'s `from`/`to`/`value`, one row per flow),
    reused completely unchanged -- the same "identical data, purely a
    rendering difference" precedent `Mark.STACKED_BAR`'s own reuse of
    `GROUPED_BAR`'s `encode_grouped_bar()` already established -- but
    drawn as a genuinely different, much simpler network layout: every
    distinct node on one straight line, evenly spaced, edges drawn as
    semicircular arcs bulging upward above it. This is ECharts.jl's
    own "Arc Diagram," a node-link diagram -- *not* this package's own
    pre-existing `Mark.ARC` (pie/donut wedges), a genuinely different
    chart type that happens to share a name; see `Mark.CHORD`'s own
    docstring for the same naming-collision note.

    Each node's own x is `index / (n - 1)` of the way across the plot
    (a single node centers). Each edge's own arc has its center at the
    horizontal midpoint between its two nodes, on the shared baseline
    (`plot_y1`, the bottom of the inner plot rect), radius half the
    distance between them -- so nodes far apart get tall arcs, nodes
    close together get shallow ones, the defining arc-diagram look.
    Deliberately *not* scaled down to fit any particular height: a
    real, deliberate v1 choice (the same kind `Mark.CHORD`'s own
    straight-rim ribbons already are) -- the true geometry is shown as
    it is, not silently compressed, so a caller with far-apart nodes
    sees exactly why (and can choose a wider `width`/taller `height`
    accordingly) rather than a chart quietly lying about relative
    distance.

    Edge stroke width scales linearly with `value / max(values)`
    (thinnest at the theme's own `line_width`, up to 3x that at the
    maximum) -- the same "value as line weight" reading `Mark.PARALLEL`
    doesn't need but a flow diagram like this one does. Edge and node
    marker color both follow the edge's own `from` node's palette
    color (`default_categorical_palette()`, indexed by first-seen
    node position -- the same convention `Mark.CHORD`'s own ribbons
    already use). A self-loop (`from[i] == to[i]`) draws nothing (a
    zero-diameter arc has no shape) rather than raising -- not an
    error, just nothing to draw.

    Every node gets its own name labeled directly beneath its own
    marker -- unlike `Mark.CHORD`, which relies on a legend instead
    (its own ring sectors are often too thin to hold a label), an arc
    diagram's nodes sit in one open row with plenty of room, so no
    legend is drawn here at all: it would just repeat what's already
    labeled once, directly, right on the diagram.
    """
    _validate_edge_encoding(plot, "Mark.ARC_DIAGRAM")

    var theme = plot._theme
    if len(plot._edges.from_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var edges = _edge_node_index(plot._edges.from_categories, plot._edges.to_categories)
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
        var frac = plot._edges.values[row] / max_value if max_value > 0.0 else 0.0
        var width = sc.line_width + sc.line_width * 2.0 * frac
        var color = palette[from_idx % len(palette)]

        var path = Path()
        path.move_to(left_x, baseline)
        path.arc_to(cx, baseline, radius, pi, 2.0 * pi)
        target.stroke_path_aa(path, color, width)

    for i in range(n):
        var color = palette[i % len(palette)]
        var px = _round_to_int(node_x[i])
        var py = _round_to_int(baseline)
        target.fill_circle_aa(px, py, _round_to_int(sc.point_radius), color)
        text_requests.append(
            _TextRequest(
                px, py + sc.tick_length + sc.label_gap + Int(sc.font_size), nodes[i], theme.text_color,
                sc.font_size, TextAlign.CENTER, theme.font_family,
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
) raises -> Canvas:
    """An arc diagram -- `Mark.ARC_DIAGRAM`, `Mark.CHORD`'s own edge
    list (`Plot.encode_chord()`'s `from_categories`/`to_categories`/
    `values`) drawn as nodes on one line connected by semicircular
    arcs instead of a circular ribbon diagram. See `_render_arc_
    diagram`'s own docstring for the full reasoning."""
    var plot = Plot().mark_arc_diagram().encode_chord(
        from_categories=from_categories, to_categories=to_categories, values=values
    )
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
