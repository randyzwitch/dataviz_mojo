"""Tests for Plot.encode_histogram()'s binning and its render as an
ordinary Mark.BAR chart.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import (
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
from dataviz.theme import Theme

from _test_helpers import _count_color, _assert_color


def test_encode_histogram_bins_match_hand_derived_counts() raises:
    # 10 values, 5 bins -- bin_width=(9.0-1.0)/5=1.6, counts hand-
    # solved via python3: [3, 3, 2, 0, 2] (bin 3, [5.8,7.4), empty --
    # confirms encode_histogram doesn't skip empty bins, they're a
    # real 0-count category like any other). 9.0 (data's max)
    # lands in the last bin (would otherwise compute an out-of-range
    # index bins itself) -- see this method's docstring for why.
    var data: List[Float64] = [1.0, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 8.0, 9.0]
    var plot = Plot().mark_bar().encode_histogram(data, bins=5)
    assert_equal(len(plot.x_categories), 5)
    assert_equal(plot.x_categories[0], "1.0-2.6")
    assert_equal(plot.x_categories[1], "2.6-4.2")
    assert_equal(plot.x_categories[2], "4.2-5.8")
    assert_equal(plot.x_categories[3], "5.8-7.4")
    assert_equal(plot.x_categories[4], "7.4-9.0")
    assert_equal(plot.y_data[0], 3.0)
    assert_equal(plot.y_data[1], 3.0)
    assert_equal(plot.y_data[2], 2.0)
    assert_equal(plot.y_data[3], 0.0)
    assert_equal(plot.y_data[4], 2.0)


def test_encode_histogram_raises_on_empty_data() raises:
    var data = List[Float64]()
    with assert_raises():
        _ = Plot().mark_bar().encode_histogram(data, bins=5)


def test_encode_histogram_raises_on_non_positive_bins() raises:
    var data: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises():
        _ = Plot().mark_bar().encode_histogram(data, bins=0)


def test_encode_histogram_raises_on_zero_span_data() raises:
    var data: List[Float64] = [5.0, 5.0, 5.0]
    with assert_raises():
        _ = Plot().mark_bar().encode_histogram(data, bins=5)


def test_render_histogram_draws_as_an_ordinary_bar_chart() raises:
    # A smoke test confirming the wiring end to end, not re-deriving
    # Mark.BAR's rendering math (already exhaustively covered by
    # test_render_bar_mark_matches_hand_derived_bar_rectangles and
    # friends -- encode_histogram() feeds the identical render path,
    # just with computed rather than given categories/counts).
    var data: List[Float64] = [1.0, 1.0, 1.0, 5.0, 9.0]
    var plot = Plot().mark_bar().encode_histogram(data, bins=3).theme(Theme(show_gridlines=False)).size(400, 300)
    var c = render(plot)
    # Bin 0 ([1.0, 3.667)) holds 3 of the 5 values -- its bar
    # should be the tallest, definitely not still just background at
    # the vertical center of the plot area.
    var mid_of_plot_area = c.get_pixel(113, 135)
    assert_true(
        mid_of_plot_area.r != 255 or mid_of_plot_area.g != 255 or mid_of_plot_area.b != 255,
        "bin 0's bar (3 of 5 values) reaches well above the plot area's midpoint",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
