"""Tests for Mark.LOLLIPOP: stem-and-point rendering (raster + SVG) --
split out of what used to be one big test_plot.mojo.
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

from _test_helpers import BG, _count_color, _assert_color


def test_render_lollipop_matches_hand_derived_stem_and_point() raises:
    # Exactly test_render_bar_mark_matches_hand_derived_bar_rectangles'
    # own data/canvas/theme (3 categories, y=[10,20,15], 400x300,
    # default margins, gridlines off) -- Mark.LOLLIPOP shares Mark.BAR's
    # own encode_categorical() data shape and _zero_baseline_y_extent
    # domain, so category "b"'s own band center (220.0, an exact value
    # -- band_start(1)=177.333 + bandwidth/2=42.667) and value-20 pixel
    # (30.952, rounds to 31 -- the same "tops at y=31" the bar test
    # already confirmed) carry over unchanged; only the *shape* drawn
    # at those coordinates differs. Confirmed via a real render() run
    # first, not derived from the formula alone.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [10.0, 20.0, 15.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_lollipop().encode_categorical(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 220, 31, t.mark_color, "circle center, category b's own value pixel")
    _assert_color(c, 220, 150, t.mark_color, "stem midpoint, well within the 2px-wide stroke")
    _assert_color(c, 210, 150, BG, "off the stem entirely -- background")
    _assert_color(c, 220, 10, BG, "above the point -- nothing drawn there")


def test_render_lollipop_svg_matches_confirmed_stem_and_point() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [10.0, 20.0, 15.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_lollipop().encode_categorical(x=x, y=y).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,250.000 L220.000,30.952" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "category b's own stem, confirmed via a real render_svg() run",
    )
    assert_true('<circle cx="220" cy="31" r="4" fill="#1e64b4"/>' in s, "category b's own point")


def test_render_lollipop_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_lollipop().encode_categorical(x=x, y=y)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
