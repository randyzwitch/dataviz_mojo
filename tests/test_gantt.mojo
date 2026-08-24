"""Tests for Mark.GANTT: bars from start/end spans (raster + SVG) -- split
out of what used to be one big test_plot.mojo.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import (
    Plot,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    _build_line_path,
    _index_of,
    _unique_categories,
)
from dataviz_mojo.theme import Theme
from dataviz_mojo import gantt

from _test_helpers import BG, _count_color, _assert_color


def test_render_gantt_matches_hand_derived_bars() raises:
    # 2 categories ("A", "B" -- short labels, so the dynamic left margin
    # stays at Theme's default 60, the same "A"/short-label convention
    # test_render_left_margin_unchanged_for_short_y_axis_labels already
    # established, sidestepping real font-metric dependence). Canvas
    # 400x300, plot area x:[60,380], y:[20,250], show_gridlines=False.
    # "A" spans [10,40], "B" spans [50,90]. Domain data = every start/end
    # value = [10,40,50,90] -> _data_extent pads 5% of the 80-span (4.0)
    # -> x-domain [6, 94]. y is now the *categorical* axis: OrdinalScale
    # over [20,250] (2 categories, step=115, padding 0.2 -> bandwidth
    # 92), category 0 ("A") landing nearer the *top* (smaller pixel y)
    # than category 1 ("B") -- confirmed directly below, not assumed.
    # Every pixel independently computed via python3 from LinearScale's/
    # OrdinalScale's formulas, then confirmed against a real
    # render() run before trusting it.
    var cats: List[String] = ["A", "B"]
    var start: List[Float64] = [10.0, 50.0]
    var end: List[Float64] = [40.0, 90.0]
    var t = Theme(show_gridlines=False)
    var c = gantt(cats, start, end, theme=t, width=400, height=300)

    _assert_color(c, 100, 60, t.mark_color, "A's bar (x:[75,184), y:[32,124)), well inside")
    _assert_color(c, 250, 180, t.mark_color, "B's bar (x:[220,365), y:[147,239)), well inside")
    _assert_color(c, 100, 140, BG, "the gap between A's and B's rows -- background")
    _assert_color(c, 200, 60, BG, "A's row, but past its bar's right edge -- background")
    _assert_color(c, 10, 60, BG, "left of the plot area entirely -- background")


def test_render_gantt_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var start: List[Float64] = [10.0, 50.0]
    var end: List[Float64] = [40.0, 90.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_gantt().encode_gantt(cats, start, end).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<rect x="75" y="32" width="109" height="92" fill="#1e64b4"/>' in s, "A's bar")
    assert_true('<rect x="220" y="147" width="145" height="92" fill="#1e64b4"/>' in s, "B's bar")


def test_render_gantt_zero_length_span_floors_to_one_pixel() raises:
    # A milestone: start == end. _render_gantt's docstring is
    # explicit this is real, informative data (a deadline marker), not
    # an absent value the way Mark.BULLET's zero-measure case is --
    # floored to 1px rather than drawn as a genuinely zero-width
    # (invisible) rect the way a naive fill_rect call would.
    var cats: List[String] = ["Launch"]
    var start: List[Float64] = [50.0]
    var end: List[Float64] = [50.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_gantt().encode_gantt(cats, start, end).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('width="1"' in s, "the milestone's bar, floored to a visible 1px width")


def test_render_gantt_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = gantt(cats, one, one, width=200, height=150)


def test_render_gantt_empty_data_only_fills_background() raises:
    var cats = List[String]()
    var empty = List[Float64]()
    var c = gantt(cats, empty, empty, width=200, height=150)
    _assert_color(c, 100, 75, BG, "no categories -- just the background fill")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
