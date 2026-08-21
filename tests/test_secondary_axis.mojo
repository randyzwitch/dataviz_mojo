"""Tests for Plot.secondary_axis(): render_layers()'s own dual-y-axis
support -- the mirrored right-edge axis line/ticks/labels (SVG + a
raster ink companion), independent per-axis domains (two very
differently-shaped series drawing at genuinely different pixel paths,
not one silently reusing the other's scale), no gridlines drawn for
the secondary domain, coexistence with a legend column (the two never
overlap), and both raise paths (a standalone plot, and every layer
calling .secondary_axis() with none left on the primary axis).
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render, render_layers, render_layers_svg
from dataviz_mojo.theme import Theme

from _test_helpers import BG, _assert_color


def test_render_layers_svg_secondary_axis_matches_hand_derived_position() raises:
    # 2 layers, no color/size encoding (so legend_reserve is 0), no
    # gridlines -- wait, gridlines stay on for this one (default Theme)
    # specifically to confirm the *secondary* domain draws none of its
    # own (see the gridline-count assertion below). Two points each,
    # canvas 400x300: primary line rises 10->20 (matches test_layers.
    # mojo's own no-legend geometry -- plot area x:[60,342], y:[20,250]
    # before the secondary axis's own reserve shrinks px1 further, to
    # 350). Secondary line falls 50->10 -- a deliberately different
    # shape/scale from the primary series, so a wrong implementation
    # that silently reused the primary y_scale would draw a visibly
    # different (flattened/off-plot) path instead of this one -- both
    # confirmed against a real render_layers_svg() run first.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1)
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis()
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = SvgCanvas(400, 300)
    render_layers_svg(svg, plots, 0, 0, 400, 300)
    var s = svg.to_string()

    assert_true(
        '<path d="M73.182,239.545 L336.818,30.455" fill="none" stroke="#1e64b4" stroke-width="2.000"'
        ' stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the primary layer's own rising path, against the primary (left) y-scale",
    )
    assert_true(
        '<path d="M73.182,30.455 L336.818,239.545" fill="none" stroke="#1e64b4" stroke-width="2.000"'
        ' stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the secondary layer's own falling path -- the opposite slope, against its own"
        " independent (right) y-scale, not the primary one",
    )
    assert_true(
        '<line x1="350" y1="20" x2="350" y2="250" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the secondary axis's own vertical line, mirrored onto the plot's right edge",
    )
    assert_true(
        '<line x1="350" y1="135" x2="355" y2="135" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "one of the secondary axis's own ticks, pointing right instead of left",
    )
    assert_true(
        '<text x="359" y="139" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="start">30</text>' in s,
        "that tick's own label, left-aligned just past it -- the mirror of the primary"
        " axis's right-aligned labels sitting just before its own ticks",
    )


def test_render_layers_svg_secondary_axis_draws_no_gridlines_of_its_own() raises:
    # Same setup as above -- exactly 6 gridlines expected (3 vertical
    # from the shared x-axis, 3 horizontal from the *primary* y-domain's
    # own 3 ticks: 10/15/20), even though the secondary y-domain has 5
    # ticks of its own (10/20/30/40/50) -- confirms none of those 5
    # spawn a 4th, 5th, 6th, 7th, 8th gridline of their own.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1)
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis()
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = SvgCanvas(400, 300)
    render_layers_svg(svg, plots, 0, 0, 400, 300)
    var s = svg.to_string()
    var count = 0
    var search_from = 0
    while True:
        var idx = s.find('stroke="#e1e1e1"', search_from)
        if idx == -1:
            break
        count += 1
        search_from = idx + 1
    assert_equal(count, 6, "only the shared x-axis's and the primary y-axis's own gridlines draw")


def test_render_layers_secondary_axis_raster_draws_ink_at_the_hand_derived_row() raises:
    # Raster-side companion to the SVG tests above -- confirms canvas_
    # mojo's own draw_line_aa actually painted the secondary axis's own
    # tick at the same (350, 135) position, not just that the SVG
    # backend's own line/text plumbing is correct.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1)
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis()
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var c = Canvas(400, 300, BG)
    render_layers(c, plots, 0, 0, 400, 300)
    _assert_color(c, 352, 135, Color(80, 80, 80), "the secondary axis's own tick, just right of its axis line")


def test_render_layers_svg_secondary_axis_coexists_with_a_legend_without_overlap() raises:
    # A color-categories-encoded Mark.POINT primary layer (so a real
    # legend column draws) alongside a secondary-axis Mark.LINE layer --
    # confirms the legend column shifts right past the secondary axis's
    # own reserved tick-label width instead of overlapping it. Confirmed
    # against a real render_layers_svg() run first: the secondary axis's
    # own line lands at x=220 (shrunk further than the no-legend case's
    # x=350 above, since legend_reserve is now folded in too), its own
    # widest tick label ("50") ends well before x=270, where the first
    # legend swatch actually starts.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_point().encode(x=x, y=y1, color_categories=cats)
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis()
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = SvgCanvas(400, 300)
    render_layers_svg(svg, plots, 0, 0, 400, 300)
    var s = svg.to_string()
    assert_true(
        '<line x1="220" y1="20" x2="220" y2="250" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the secondary axis's own line, shrunk further left to also make room for the legend",
    )
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "the legend's own first swatch, starting well clear of the secondary axis's own labels",
    )


def test_render_secondary_axis_raises_on_standalone_render() raises:
    # Plot.secondary_axis() only means anything inside render_layers()/
    # render_layers_svg() -- a standalone render() call must raise
    # rather than silently ignoring it (there's no second series for it
    # to pair against).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).secondary_axis()
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_layers_raises_when_every_layer_is_secondary() raises:
    # At least one layer must stay on the primary axis -- every layer
    # calling .secondary_axis() leaves nothing for "secondary" to mean
    # relative to, so render_layers() must raise rather than silently
    # treating it as an ordinary single shared axis.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var a = Plot().mark_line().encode(x=x, y=y1).secondary_axis()
    var b = Plot().mark_line().encode(x=x, y=y2).secondary_axis()
    var plots = List[Plot]()
    plots.append(a^)
    plots.append(b^)
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
