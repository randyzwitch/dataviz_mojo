"""Generic Plot.encode()/render() validation and utility-function tests
that aren't specific to any one Mark type -- split out of what used to
be one big test_plot.mojo.
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


def test_render_raises_on_mismatched_x_y_lengths() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0]
    var plot = Plot().encode(x=x, y=y)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_empty_data_only_fills_background() raises:
    # render() always fills with theme.background regardless of
    # whatever the canvas was constructed with (Plot owns the whole
    # canvas it's given -- see plot.mojo's own docstring), so the
    # canvas's own initial fill color (10,20,30) must NOT survive.
    var plot = Plot()  # no encode() call -- x_data/y_data both empty
    var c = Canvas(50, 40, Color(10, 20, 30))
    render(c, plot)
    var expected = Theme.default().background
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, expected.r)
            assert_equal(p.g, expected.g)
            assert_equal(p.b, expected.b)


def test_render_respects_custom_theme_colors() raises:
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var custom = Theme(background=Color(20, 20, 20), mark_color=Color(255, 0, 0))
    var plot = Plot().mark_point().encode(x=x, y=y).theme(custom)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    # Far corner, untouched by any mark/axis/gridline -- pure background.
    var corner = c.get_pixel(399, 0)
    assert_equal(corner.r, 20)
    assert_equal(corner.g, 20)
    assert_equal(corner.b, 20)

    var mark_pixel = c.get_pixel(220, 135)
    assert_equal(mark_pixel.r, 255)
    assert_equal(mark_pixel.g, 0)
    assert_equal(mark_pixel.b, 0)


def test_render_gridlines_flag_actually_controls_gridline_pixels() raises:
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var gridline_color = Color(225, 225, 225)

    var c_on = Canvas(400, 300, BG)
    render(c_on, Plot().mark_point().encode(x=x, y=y).theme(Theme(show_gridlines=True)))
    assert_true(_count_color(c_on, gridline_color) > 0)

    var c_off = Canvas(400, 300, BG)
    render(c_off, Plot().mark_point().encode(x=x, y=y).theme(Theme(show_gridlines=False)))
    assert_equal(_count_color(c_off, gridline_color), 0)


def test_render_raises_on_mismatched_color_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var color: List[Float64] = [1.0, 2.0]
    var plot = Plot().encode(x=x, y=y, color=color)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_raises_on_mismatched_size_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var size: List[Float64] = [1.0, 2.0]
    var plot = Plot().encode(x=x, y=y, size=size)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_unique_categories_preserves_first_seen_order() raises:
    var data: List[String] = ["b", "a", "b", "c", "a"]
    var unique = _unique_categories(data)
    assert_equal(len(unique), 3)
    assert_equal(unique[0], "b")
    assert_equal(unique[1], "a")
    assert_equal(unique[2], "c")


def test_index_of_finds_positions_and_reports_missing_as_negative_one() raises:
    var data: List[String] = ["x", "y", "z"]
    assert_equal(_index_of(data, "x"), 0)
    assert_equal(_index_of(data, "z"), 2)
    assert_equal(_index_of(data, "q"), -1)


def test_render_raises_when_color_and_color_categories_both_given() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var color: List[Float64] = [1.0, 2.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().encode(x=x, y=y, color=color, color_categories=cats)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_raises_on_mismatched_color_categories_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().encode(x=x, y=y, color_categories=cats)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_svg_raises_on_mismatched_x_y_lengths() raises:
    # render_svg()'s validation isn't a separate check -- it's the
    # exact same _render_generic core render() itself calls, so a
    # mismatched-length Plot raises through either entry point
    # identically. Confirms that sharing, not re-derives the check.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0]
    var svg = SvgCanvas(200, 150)
    var plot = Plot().encode(x=x, y=y)
    with assert_raises():
        render_svg(svg, plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
