"""Tests for Plot.annotate_vline()/Plot.annotate_point(): vertical
reference-line and single-point-marker placement (SVG + raster ink
companions), out-of-range values/points drawing nothing for each, and
the mark-support boundary (Mark.LINE supported, Mark.BAR raises --
narrower than annotate_line()/annotate_area()'s own support, since
neither has a continuous x-axis to place anything against on the nine
_CategoricalFrame-sharing marks).
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme

from _test_helpers import BG, _assert_color


def test_render_svg_annotate_vline_matches_hand_derived_position() raises:
    # Mark.LINE, 2 points (10 -> 20), no gridlines -- x-domain pads to
    # roughly [0.95, 2.05] (5% of span 1.0). annotate_vline(1.5)'s own
    # column maps to px=220 -- confirmed against a real render_svg() run
    # first, canvas 400x300, plot area x:[60,380], y:[20,250]. Its own
    # label sits just right of the line, near the plot's own top edge.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_vline(1.5, label="mid").theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot, 0, 0, 400, 300)
    var s = svg.to_string()
    assert_true(
        '<line x1="220" y1="20" x2="220" y2="250" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the vertical reference line itself, spanning the full inner plot height",
    )
    assert_true(
        '<text x="224" y="32" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="start">mid</text>' in s,
        "the line's own label, left-aligned just right of it, near the top edge",
    )


def test_render_svg_annotate_point_matches_hand_derived_position() raises:
    # Same plot, a point at (1.2, 15.0) -- deliberately a different x
    # than the vline test above, so the two annotation types' own ink
    # never overlaps in a raster ink check. Confirmed against a real
    # render_svg() run first: cx=133, cy=135 (the same row the "15"
    # y-tick lands on), r=4 (Theme's own default point_radius).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_point(1.2, 15.0, label="here").theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot, 0, 0, 400, 300)
    var s = svg.to_string()
    assert_true(
        '<circle cx="133" cy="135" r="4" fill="#969696"/>' in s,
        "the point marker itself, at the data coordinate's own pixel position",
    )
    assert_true(
        '<text x="133" y="127" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="middle">here</text>' in s,
        "the point's own label, centered just above the marker",
    )


def test_render_annotate_vline_raster_draws_ink_at_the_hand_derived_column() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_vline(1.5).theme(
        Theme(show_gridlines=False)
    )
    var c = Canvas(400, 300, BG)
    render(c, plot)
    _assert_color(c, 220, 100, Color(150, 150, 150), "the vline's own ink, well inside the plot height")


def test_render_annotate_point_raster_draws_ink_at_the_hand_derived_position() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_point(1.2, 15.0).theme(
        Theme(show_gridlines=False)
    )
    var c = Canvas(400, 300, BG)
    render(c, plot)
    _assert_color(c, 133, 135, Color(150, 150, 150), "the point marker's own center pixel")


def test_render_annotate_vline_out_of_range_value_draws_nothing() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_vline(5.0, label="gonevl").theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot, 0, 0, 400, 300)
    var s = svg.to_string()
    assert_true(">gonevl<" not in s, "an out-of-domain vline draws no label at all")
    assert_true('stroke="#969696"' not in s, "an out-of-domain vline draws no line at all")


def test_render_annotate_point_out_of_range_draws_nothing() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_point(1.5, 100.0, label="gonept").theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot, 0, 0, 400, 300)
    var s = svg.to_string()
    assert_true(">gonept<" not in s, "an out-of-domain point draws no label at all")
    assert_true("<circle" not in s, "an out-of-domain point draws no marker at all")


def test_render_annotate_vline_raises_on_unsupported_mark() raises:
    # Mark.BAR's own x-axis is categorical -- no continuous x value a
    # vertical line could mean anything against, unlike annotate_line()/
    # annotate_area(), which both support Mark.BAR just fine.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).annotate_vline(1.5)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_annotate_point_raises_on_unsupported_mark() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).annotate_point(0.5, 1.5)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
