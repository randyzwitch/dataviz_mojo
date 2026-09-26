"""`encode()`'s `x_err`/`x_err_lower`/`x_err_upper` (#840): the
horizontal counterpart of the y error bars, drawn on `Mark.POINT`,
`LINE` and `EFFECT_SCATTER` under the same rules.

The checks read the output rather than the source: an SVG line whose
two ends sit at the same y and span the whisker, a caps count, an x
axis wide enough to hold the whisker, the messages the y bars already
give, and a y-only chart that is byte for byte what it was.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from dataviz import render, render_layers, render_svg
from dataviz.plot import Plot


def _xs() -> List[Float64]:
    return [1.0, 2.0, 3.0]


def _ys() -> List[Float64]:
    return [2.0, 4.0, 3.0]


def _count(s: String, needle: String) -> Int:
    var n = 0
    var at = 0
    while True:
        var i = s.find(needle, at)
        if i < 0:
            return n
        n += 1
        at = i + needle.byte_length()


def _horizontal_lines(svg: String) -> Int:
    """`<line>` elements whose `y1` equals their `y2` and whose `x1`
    differs from `x2`, each attribute read from the same element."""
    var n = 0
    var at = 0
    while True:
        var i = svg.find("<line ", at)
        if i < 0:
            return n
        var j = svg.find("/>", i)
        var el = String(svg[byte=i:j])
        at = j
        var x1 = _attr(el, "x1")
        var x2 = _attr(el, "x2")
        var y1 = _attr(el, "y1")
        var y2 = _attr(el, "y2")
        if y1 == y2 and x1 != x2 and y1 != "":
            n += 1


def _attr(el: String, name: String) -> String:
    var key = " " + name + '="'
    var i = el.find(key)
    if i < 0:
        return ""
    var start = i + key.byte_length()
    var end = el.find('"', start)
    return String(el[byte=start:end])


def test_x_err_draws_one_horizontal_whisker_per_point_on_points() raises:
    var plain = render_svg(
        Plot()
        .mark_point()
        .encode(_xs(), _ys())
        .scale_x_domain(0.0, 4.0)
        .scale_y_domain(0.0, 5.0)
    ).to_string()
    var with_x = render_svg(
        Plot()
        .mark_point()
        .encode(_xs(), _ys(), x_err=[0.5, 0.5, 0.5])
        .scale_x_domain(0.0, 4.0)
        .scale_y_domain(0.0, 5.0)
    ).to_string()
    # Three whiskers, each a horizontal bar; the caps are vertical.
    assert_equal(_horizontal_lines(with_x) - _horizontal_lines(plain), 3)
    assert_equal(_count(with_x, "<line ") - _count(plain, "<line "), 9)


def test_x_err_on_a_line_and_asymmetric_bounds() raises:
    var plain = render_svg(
        Plot()
        .mark_line()
        .encode(_xs(), _ys())
        .scale_x_domain(0.0, 4.0)
        .scale_y_domain(0.0, 5.0)
    ).to_string()
    var with_x = render_svg(
        Plot()
        .mark_line()
        .encode(
            _xs(),
            _ys(),
            x_err_lower=[0.2, 0.2, 0.2],
            x_err_upper=[0.6, 0.6, 0.6],
        )
        .scale_x_domain(0.0, 4.0)
        .scale_y_domain(0.0, 5.0)
    ).to_string()
    assert_equal(_count(with_x, "<line ") - _count(plain, "<line "), 9)


def test_x_and_y_err_together_draw_a_cross() raises:
    var plain = render_svg(
        Plot()
        .mark_point()
        .encode(_xs(), _ys())
        .scale_x_domain(0.0, 4.0)
        .scale_y_domain(0.0, 5.0)
    ).to_string()
    var both = render_svg(
        Plot()
        .mark_point()
        .encode(_xs(), _ys(), y_err=[0.5, 0.5, 0.5], x_err=[0.5, 0.5, 0.5])
        .scale_x_domain(0.0, 4.0)
        .scale_y_domain(0.0, 5.0)
    ).to_string()
    assert_equal(_count(both, "<line ") - _count(plain, "<line "), 18)


def test_the_x_domain_widens_to_hold_the_whisker() raises:
    # x in [1, 3] ticks 1.0 to 3.0. A half-width of 2 puts the whisker
    # ends at -1 and 5, and the x axis has to reach them: its ticks run
    # 0, 2, 4. Without the widening the ticks would not move.
    var plain = render_svg(Plot().mark_point().encode(_xs(), _ys())).to_string()
    var widened = render_svg(
        Plot().mark_point().encode(_xs(), _ys(), x_err=[2.0, 2.0, 2.0])
    ).to_string()
    assert_equal(_count(plain, ">1.0</text>"), 1)
    assert_equal(_count(widened, ">1.0</text>"), 0)
    assert_equal(_count(widened, ">0</text>"), 1)
    assert_equal(_count(widened, ">4</text>"), 1)


def test_x_err_follows_the_y_err_rules() raises:
    with assert_raises(contains="x_err must be the same length as x/y"):
        _ = render(Plot().mark_point().encode(_xs(), _ys(), x_err=[1.0]))
    with assert_raises(contains="x_err values must be >= 0"):
        _ = render(
            Plot().mark_point().encode(_xs(), _ys(), x_err=[1.0, -1.0, 1.0])
        )
    with assert_raises(
        contains="x_err_lower and x_err_upper must be given together"
    ):
        _ = render(
            Plot()
            .mark_point()
            .encode(_xs(), _ys(), x_err_lower=[1.0, 1.0, 1.0])
        )
    with assert_raises(
        contains="x_err and x_err_lower/x_err_upper are mutually exclusive"
    ):
        _ = render(
            Plot()
            .mark_point()
            .encode(
                _xs(),
                _ys(),
                x_err=[1.0, 1.0, 1.0],
                x_err_lower=[1.0, 1.0, 1.0],
                x_err_upper=[1.0, 1.0, 1.0],
            )
        )
    with assert_raises(
        contains="x_err is only supported for Mark.POINT/LINE/EFFECT_SCATTER"
    ):
        _ = render(
            Plot().mark_area().encode(_xs(), _ys(), x_err=[1.0, 1.0, 1.0])
        )


def test_x_err_draws_in_a_layer() raises:
    var plain = render_layers(
        Plot().mark_point().encode(_xs(), _ys()),
        Plot().mark_line().encode(_xs(), _ys()),
    )
    var with_x = render_layers(
        Plot().mark_point().encode(_xs(), _ys(), x_err=[0.5, 0.5, 0.5]),
        Plot().mark_line().encode(_xs(), _ys()),
    )
    var differs = False
    for y in range(plain.height):
        for x in range(plain.width):
            if plain.get_pixel(x, y) != with_x.get_pixel(x, y):
                differs = True
                break
        if differs:
            break
    assert_true(differs)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
