"""Tests for Plot.annotate_line(): reference-line placement (raster +
SVG), the mark-support boundary (Mark.BAR/LINE supported, Mark.ARC
raises), out-of-range values drawing nothing, and multiple lines
stacking via repeated calls.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import bar

from _test_helpers import BG, _assert_color


def test_render_svg_annotate_line_matches_hand_derived_position() raises:
    # 2 categories (A=10, B=20), no gridlines/legend -- the same no-
    # legend geometry test_render_svg_bar_mark_matches_confirmed_rect's
    # own case establishes for this canvas size: plot area x:[60,380],
    # y:[20,250]. _zero_baseline_y_extent([10,20]) pads to domain
    # [0, 21.0] (span 20, 5% pad 1.0), so annotate_line(15.0)'s pixel row is the *same* one the y=15 tick already lands on --
    # confirmed against a real render_svg() run first: y=86 (the
    # tick's label sits at y=90, offset by the same +4 baseline
    # nudge every y-axis tick label already carries). The line spans
    # the full inner width (60 to 380); its label right-aligns
    # just inside the right edge, y=86-4=82.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var svg = SvgCanvas(400, 300)
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .annotate_line(15.0, label="mid")
        .theme(Theme(show_gridlines=False))
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="60" y1="86" x2="380" y2="86" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the reference line itself, spanning the full inner plot width",
    )
    assert_true(
        '<text x="376" y="82" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">mid</text>' in s,
        "the line's label, right-aligned just above it",
    )


def test_render_annotate_line_raster_draws_ink_at_the_hand_derived_row() raises:
    # Raster-side companion to the SVG test above -- confirms canvas_
    # mojo.draw_line_aa actually painted at the same y=86 row, not just
    # that the SVG backend's text/line plumbing is correct.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var c = bar(cats, vals, width=400, height=300, theme=Theme(show_gridlines=False))
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).annotate_line(15.0).theme(
        Theme(show_gridlines=False)
    )
    var c2 = Canvas(400, 300, BG)
    render(c2, plot)
    _assert_color(c2, 220, 86, Color(150, 150, 150), "the reference line's ink, well inside the plot width")


def test_render_annotate_line_out_of_range_value_draws_nothing() raises:
    # A value outside the mark's padded domain ([0, 21.0] for this
    # data) must draw neither a line nor a label -- not clamped to an
    # edge, not extrapolated off-plot into the chrome above (a real bug
    # this exact scenario caught during development -- see _draw_
    # annotation_lines's docstring). 25.0 is past the domain's 21.0 max.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var svg = SvgCanvas(400, 300)
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .annotate_line(25.0, label="out of range")
        .theme(Theme(show_gridlines=False))
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true("out of range" not in s, "an out-of-domain annotation draws no label at all")
    assert_true('stroke="#969696"' not in s, "an out-of-domain annotation draws no line at all")


def test_render_annotate_line_multiple_calls_all_draw() raises:
    # .annotate_line() is additive, not a single-slot setter -- two
    # calls both draw, confirmed by counting real annotation-colored
    # <line> elements in the SVG output.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var svg = SvgCanvas(400, 300)
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .annotate_line(5.0, label="low")
        .annotate_line(15.0, label="high")
        .theme(Theme(show_gridlines=False))
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    var count = 0
    var search_from = 0
    while True:
        var idx = s.find('stroke="#969696"', search_from)
        if idx == -1:
            break
        count += 1
        search_from = idx + 1
    assert_equal(count, 2, "both annotation lines draw, not just the most recent call")


def test_render_annotate_line_raises_on_unsupported_mark() raises:
    # Mark.ARC has no continuous y-axis at all -- annotate_line() must
    # raise a clear error rather than silently drawing nothing or
    # drawing somewhere meaningless, the same "raise on a setting that
    # can't apply" rule x_title/y_title-on-Mark.ARC already follows.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_arc().encode_categorical(x=cats, y=vals).annotate_line(1.5)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
