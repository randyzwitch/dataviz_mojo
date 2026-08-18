"""Tests for Mark.BOX (boxplot): box/whiskers/outlier rendering (raster +
SVG) and encode_boxplot() validation -- split out of what used to be one
big test_plot.mojo.
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
from dataviz_mojo import box

from _test_helpers import BG, _count_color, _assert_color


def test_render_boxplot_matches_hand_derived_box_whiskers_and_outlier() raises:
    # 2 categories: "A" = [2,4,4,4,5,5,7,9,20] (q1=4, median=5, q3=7,
    # low_whisker=2, high_whisker=9, one outlier at 20 -- 1.5*IQR fence
    # is [4-4.5, 7+4.5]=[-0.5, 11.5], so 20 is the only value beyond
    # it), "B" = [10,12,14,15,18] (q1=12, median=14, q3=15, low=10,
    # high=18, no outliers -- fence [7.5, 19.5] contains every value).
    # Both hand-derived via the same linear-interpolation percentile
    # `_box_stats` itself uses (independently reimplemented in Python,
    # not just re-run through the Mojo code, before trusting these).
    # Domain = _data_extent over every low/high/outlier value
    # ([2,9,10,18,20]) = [1.1, 20.9], 2 categories over [60,380] (band
    # centers 140/300, bandwidth 128, half-width 64, cap half-width 32)
    # -- every pixel below confirmed via a real render() run first.
    # Built via Plot/Canvas/render() directly, not box() -- these are
    # exact hand-derived pixel positions (see this function's own
    # comment above), and box()'s own output is supersampled-then-
    # downsampled internally now (see dataviz_mojo.plot._rendered's
    # own docstring), which can shift a thin axis-color line's exact
    # footprint by a pixel or so relative to this hand-derived math.
    # render() itself stays unsupersampled -- see its own docstring --
    # so this exact check still holds there.
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var t = Theme(show_gridlines=False)
    var c = Canvas(400, 300, BG)
    render(c, Plot().mark_box().encode_boxplot(cats, values).theme(t))

    _assert_color(c, 140, 200, t.mark_color, "A: inside the box (between q1 and q3)")
    _assert_color(c, 140, 205, t.axis_color, "A: the median line, drawn over the box fill")
    _assert_color(c, 140, 170, t.axis_color, "A: the upper whisker, between q3 and high")
    _assert_color(c, 120, 158, t.axis_color, "A: the high-whisker cap")
    _assert_color(c, 140, 30, t.mark_color, "A: the one outlier point, at value 20")
    _assert_color(c, 300, 105, t.mark_color, "B: inside the box")
    _assert_color(c, 300, 100, t.axis_color, "B: the median line")
    _assert_color(c, 300, 70, t.axis_color, "B: the lower whisker, between q1 and low")
    _assert_color(c, 190, 150, BG, "the gap between A's and B's own bands -- background")


def test_render_boxplot_svg_matches_confirmed_rects_and_outlier() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_box().encode_boxplot(cats, values).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<rect x="76" y="181" width="128" height="35" fill="#1e64b4"/>' in s, "A's own box (q1 to q3)")
    assert_true('<rect x="236" y="89" width="128" height="35" fill="#1e64b4"/>' in s, "B's own box (q1 to q3)")
    assert_true('<circle cx="140" cy="30" r="4" fill="#1e64b4"/>' in s, "A's own single outlier, at value 20")


def test_encode_boxplot_raises_on_mismatched_length() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = box(cats, values)


def test_encode_boxplot_raises_on_empty_category_values() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[1.0, 2.0], List[Float64]()]
    with assert_raises():
        _ = box(cats, values)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
