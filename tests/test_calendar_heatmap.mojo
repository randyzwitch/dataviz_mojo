"""Tests for Mark.CALENDAR_HEATMAP: date-to-grid-cell placement
(day-of-week row, week-of-year column) and color-scale reuse from
Mark.HEATMAP (raster + SVG) -- see calendar_heatmap.mojo's docstrings for the date-math rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import calendar_heatmap

from _test_helpers import BG, _assert_color


def test_render_calendar_heatmap_matches_hand_derived_cells() raises:
    # 2024-01-01 (a real-world Monday, confirmed independently, not
    # just trusted from the formula), 2024-01-07 (the following
    # Sunday -- 6 days later, wrapping to the *next* week's column since Sunday starts a new week here), and 2024-12-31 (a
    # real-world Tuesday, the year's last day, in the year's last column). Values [1.0, 2.0, 3.0] -- min/mid/max of the color
    # domain, so the first and third cells read directly off Theme's
    # own color_scale_low/high, no ColorScale interpolation math to
    # trust blindly.
    #
    # Canvas 900x300, show_legend=False: plot area x:[60,880],
    # y:[20,250] (top margin grows by one font-size + label-gap for
    # the month-label row above the grid). 2024 is a leap year (366
    # days) -> 53 week-columns. Every rect below (see this file's SVG test):
    # Jan 1 (Mon, row 1, col 0) -> rect(60,67,15,31); Jan 7 (Sun, row
    # 0, col 1) -> rect(75,36,15,31); Dec 31 (Tue, row 2, col 52) ->
    # rect(865,97,15,31). Interior points sampled well inside each
    # rect's bounds, not on an edge.
    #
    # value=2.0 sits at the color domain's exact midpoint (t=0.5)
    # -- lands on Theme's color_scale_mid exactly, not an
    # interpolated blend: ColorScale.from_theme() adds that as a real
    # stop at offset 0.5 (see its docstring), and _color_at_t
    # brackets an exact-offset match to itself (before == after), no
    # RGB-space interpolation involved at all. Read directly off Theme
    # the same way the min/max cells already are, not hand-derived.
    var dates: List[String] = ["2024-01-01", "2024-01-07", "2024-12-31"]
    var values: List[Float64] = [1.0, 2.0, 3.0]
    var t = Theme(show_legend=False)
    var c = calendar_heatmap(dates, values, theme=t, width=900, height=300)

    _assert_color(c, 67, 82, t.color_scale_low, "Jan 1 (Mon), value 1.0 -- the color domain's min")
    _assert_color(c, 82, 51, t.color_scale_mid, "Jan 7 (Sun), value 2.0 -- the domain's exact midpoint")
    _assert_color(c, 872, 112, t.color_scale_high, "Dec 31 (Tue), value 3.0 -- the color domain's max")
    _assert_color(c, 10, 10, BG, "well outside the whole plot area -- background")


def test_render_calendar_heatmap_svg_matches_confirmed_rects() raises:
    var dates: List[String] = ["2024-01-01", "2024-01-07", "2024-12-31"]
    var values: List[Float64] = [1.0, 2.0, 3.0]
    var svg = SvgCanvas(900, 300)
    var plot = Plot().mark_calendar_heatmap().encode_calendar(dates=dates, values=values).theme(
        Theme(show_legend=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<rect x="60" y="67" width="15" height="31" fill="#3c6ec8"/>' in s, "Jan 1 (Mon), col 0")
    assert_true('<rect x="75" y="36" width="15" height="31" fill="#ebebeb"/>' in s, "Jan 7 (Sun), col 1")
    assert_true('<rect x="865" y="97" width="15" height="31" fill="#dc5a28"/>' in s, "Dec 31 (Tue), col 52")


def test_render_calendar_heatmap_raises_on_mismatched_length() raises:
    var dates: List[String] = ["2024-01-01", "2024-01-02"]
    var values: List[Float64] = [1.0]
    with assert_raises():
        _ = calendar_heatmap(dates, values, width=200, height=150)


def test_render_calendar_heatmap_raises_on_mismatched_year() raises:
    var dates: List[String] = ["2024-01-01", "2025-01-01"]
    var values: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = calendar_heatmap(dates, values, width=200, height=150)


def test_render_calendar_heatmap_empty_data_only_fills_background() raises:
    var dates = List[String]()
    var values = List[Float64]()
    var c = calendar_heatmap(dates, values, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no dates at all -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
