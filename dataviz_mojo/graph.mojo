from std.math import cos, pi, sin

from canvas_mojo.color import Color
from canvas_mojo.geometry import _round_to_int
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
    _index_of,
    _min_max,
    _rendered,
    _unique_categories,
)
from dataviz_mojo.theme import Theme


def _render_graph[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.GRAPH` plot: `Mark.CHORD`'s own edge-list shape
    (`encode_chord()`'s `from`/`to`/`value`), reused completely
    unchanged (the same reuse precedent `Mark.ARC_DIAGRAM`'s own
    docstring already establishes for this exact data), drawn as a
    third genuinely different network layout: every distinct node
    evenly spaced *around* a circle (`Mark.ARC`'s own start-at-12-
    o'clock, sweep-clockwise convention, reused for node position only
    -- there's no wedge here), edges drawn as *straight* lines cutting
    across the interior, rather than `Mark.CHORD`'s own ring sectors
    plus curved ribbons hugging the rim, or `Mark.ARC_DIAGRAM`'s own
    nodes-on-a-line-plus-arcs-above.

    A deliberately simple, deterministic circular layout -- not a real
    force-directed simulation (which iteratively repositions nodes to
    minimize edge crossings/overlap, the layout most general-purpose
    graph-drawing tools actually use), a real v1 scope choice: a fixed
    node order around a circle is easy to hand-verify pixel-for-pixel,
    which this package's whole test methodology depends on, while a
    physics simulation's own settled positions generally aren't (see
    `Mark.BEESWARM`'s own docstring for the identical "not a full
    physics simulation, a deterministic swarm instead" reasoning
    applied to a completely different layout problem).

    Edge stroke width scales with `value/max(values)`, edge and node
    marker color both follow the edge's own `from` node's palette
    color -- the same conventions `Mark.ARC_DIAGRAM` already
    establishes for this identical data shape. A self-loop (`from[i]
    == to[i]`) draws nothing. Every node is labeled just outside its
    own position on the circle, aligned by which side of center it
    falls on (left-aligned on the right half, right-aligned on the
    left half, centered at the top/bottom -- the same alignment rule
    `Mark.RADAR`'s own axis labels already use for the identical
    "label sits just outside a point on a circle" problem) -- no
    legend, the same "already labeled directly, nothing left for a
    legend to add" reasoning `Mark.ARC_DIAGRAM` already gives.
    """
    if len(plot._chord_from) != len(plot._chord_to) or len(plot._chord_value) != len(plot._chord_from):
        raise Error(
            "Plot.encode_chord(): from_categories, to_categories, and"
            " values must all have the same length (got "
            + String(len(plot._chord_from))
            + " from_categories, "
            + String(len(plot._chord_to))
            + " to_categories, "
            + String(len(plot._chord_value))
            + " values)"
        )

    var theme = plot._theme
    if len(plot._chord_from) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    for v in plot._chord_value:
        if v < 0.0:
            raise Error("Plot: Mark.GRAPH values must be non-negative (got " + String(v) + ")")

    var combined = List[String]()
    for v in plot._chord_from:
        combined.append(v)
    for v in plot._chord_to:
        combined.append(v)
    var nodes = _unique_categories(combined)
    var n = len(nodes)

    var sc = _Scaled(theme)
    var plot_x0 = ox0 + sc.margin_left
    var plot_y0 = oy0 + sc.margin_top
    var plot_x1 = ox1 - sc.margin_right
    var plot_y1 = oy1 - sc.margin_bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var max_radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9

    var node_x = List[Float64](capacity=n)
    var node_y = List[Float64](capacity=n)
    for i in range(n):
        var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
        node_x.append(cx + max_radius * cos(angle))
        node_y.append(cy + max_radius * sin(angle))

    var palette = default_categorical_palette()
    var value_mm = _min_max(plot._chord_value)
    var max_value = value_mm.max

    for row in range(len(plot._chord_from)):
        var from_idx = _index_of(nodes, plot._chord_from[row])
        var to_idx = _index_of(nodes, plot._chord_to[row])
        if from_idx == to_idx:
            continue
        var frac = plot._chord_value[row] / max_value if max_value > 0.0 else 0.0
        var width = sc.line_width + sc.line_width * 2.0 * frac
        var color = palette[from_idx % len(palette)]
        target.draw_line_aa(
            _round_to_int(node_x[from_idx]), _round_to_int(node_y[from_idx]),
            _round_to_int(node_x[to_idx]), _round_to_int(node_y[to_idx]), color, width,
        )

    var text_requests = List[_TextRequest]()
    for i in range(n):
        var angle = -pi / 2.0 + Float64(i) * (2.0 * pi / Float64(n))
        var color = palette[i % len(palette)]
        var px = _round_to_int(node_x[i])
        var py = _round_to_int(node_y[i])
        target.fill_circle_aa(px, py, _round_to_int(sc.point_radius), color)

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
                _round_to_int(label_x), _round_to_int(label_y) + Int(sc.font_size * 0.35), nodes[i],
                theme.text_color, sc.font_size, align, theme.font_family,
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
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A network graph -- `Mark.GRAPH`, `Mark.CHORD`'s own edge list
    (`Plot.encode_chord()`'s `from_categories`/`to_categories`/
    `values`) drawn as nodes evenly spaced around a circle, connected
    by straight lines cutting across the interior. See `_render_graph`'s
    own docstring for the full reasoning."""
    var plot = Plot().mark_graph().encode_chord(
        from_categories=from_categories, to_categories=to_categories, values=values
    )
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
