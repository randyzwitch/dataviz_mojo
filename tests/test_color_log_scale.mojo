"""Logarithmic color normalization (#370).

A linear ramp cannot resolve values spread over orders of magnitude: on a
1-to-10,000 domain everything below 1,000 sits in the first tenth of the
ramp and reads as one color. `Plot.scale_color_log()` normalizes by
`log10` instead, so equal *ratios* get equal color distance.

#370's acceptance criterion for this part is "log-spaced values have
evenly spaced normalized positions", which is what
`test_log_spaced_values_are_evenly_spaced_in_color` checks directly
rather than by eye.

This is the one piece of #370 not entangled with missing-data handling
(#367, on hold): out-of-range and missing colors have to wait for what a
gap means, and a log domain does not.
"""

from std.math import log10
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)

from canvas.color import Color

from dataviz import Theme
from dataviz.core.color_scale import (
    ColorScale,
    _ColorDomainOverride,
    _color_scale_for,
)
from dataviz.plot import Plot, render


def _decades() -> List[Float64]:
    var v = List[Float64]()
    v.append(1.0)
    v.append(10.0)
    v.append(100.0)
    v.append(1000.0)
    v.append(10000.0)
    return v^


def _xs(n: Int) -> List[Float64]:
    var v = List[Float64]()
    for i in range(n):
        v.append(Float64(i))
    return v^


def _log_scale(lo: Float64, hi: Float64) raises -> ColorScale:
    var d = _ColorDomainOverride()
    d.log = True
    return _color_scale_for(Theme(), d, lo, hi)


def _linear_scale(lo: Float64, hi: Float64) raises -> ColorScale:
    return _color_scale_for(Theme(), _ColorDomainOverride(), lo, hi)


def _same(a: Color, b: Color) -> Bool:
    return a.r == b.r and a.g == b.g and a.b == b.b


def _rgb(c: Color) -> String:
    return "(" + String(c.r) + "," + String(c.g) + "," + String(c.b) + ")"


def _unit() raises -> ColorScale:
    """A linear scale over [0, 1], so `color_at(t)` *is* the ramp at
    position `t`.

    The reference every test below compares against. An earlier version
    used the sum of a color's channels as a stand-in for position along
    the ramp, which is wrong: the default ramp runs dark blue to green
    to yellow and its channel sum is not monotonic, so the measure said
    the spacing was uneven when the spacing was fine.
    """
    return _color_scale_for(Theme(), _ColorDomainOverride(), 0.0, 1.0)


def test_log_spaced_values_are_evenly_spaced_in_color() raises:
    """#370's stated acceptance criterion for this part.

    Five decades from 1 to 10,000. Under a log normalization decade `k`
    is exactly `k / 4` of the way along the ramp, so its color must be
    the ramp's own color at that position, compared against a linear
    scale over [0, 1] that indexes the same stops.
    """
    var scale = _log_scale(1.0, 10000.0)
    var unit = _unit()
    var vals = _decades()
    for k in range(len(vals)):
        var got = scale.color_at(vals[k])
        var want = unit.color_at(Float64(k) / 4.0)
        assert_true(
            _same(got, want),
            "decade "
            + String(k)
            + " (value "
            + String(vals[k])
            + ") is "
            + _rgb(got)
            + " but position "
            + String(Float64(k) / 4.0)
            + " of the ramp is "
            + _rgb(want),
        )


def test_the_linear_scale_is_the_thing_this_fixes() raises:
    # The control. On a linear 1-to-10,000 ramp the value 10 sits at
    # (10 - 1) / 9999, which is nine ten-thousandths along: visually the
    # low end. Four of the five decades crowd into the first percent,
    # which is the defect log normalization exists to remove.
    var linear = _linear_scale(1.0, 10000.0)
    var unit = _unit()
    assert_true(
        _same(linear.color_at(10.0), unit.color_at(9.0 / 9999.0)),
        "the linear scale did not put 10 at the bottom of the ramp",
    )
    assert_true(
        not _same(linear.color_at(10.0), unit.color_at(0.25)),
        (
            "a linear ramp already spreads the decades evenly, so there is"
            " nothing for the log scale to fix"
        ),
    )


def test_the_ends_of_the_domain_pin_to_the_ends_of_the_ramp() raises:
    var scale = _log_scale(1.0, 10000.0)
    var unit = _unit()
    assert_true(
        _same(scale.color_at(1.0), unit.color_at(0.0)), "the low end moved"
    )
    assert_true(
        _same(scale.color_at(10000.0), unit.color_at(1.0)),
        "the high end moved",
    )


def test_a_midpoint_lands_where_the_logarithm_says() raises:
    # 100 is the geometric mean of 1 and 10,000, so it sits exactly
    # halfway along a log ramp and a hundredth of the way along a linear
    # one. Both halves asserted: the second is what makes the first mean
    # something.
    var scale = _log_scale(1.0, 10000.0)
    var unit = _unit()
    assert_true(
        _same(scale.color_at(100.0), unit.color_at(0.5)),
        "the geometric mean did not land mid-ramp",
    )
    var linear = _linear_scale(1.0, 10000.0)
    assert_true(
        not _same(linear.color_at(100.0), unit.color_at(0.5)),
        "the linear scale also put 100 mid-ramp, so this proves nothing",
    )


def test_a_non_positive_domain_raises_at_render_time() raises:
    # The domain is only known once the mark's data is in, so the check
    # cannot live in the builder.
    var y = List[Float64]()
    var color = List[Float64]()
    for i in range(4):
        y.append(Float64(i))
        color.append(Float64(i) - 1.0)  # spans zero
    with assert_raises(contains="strictly positive domain"):
        _ = render(
            Plot()
            .mark_point()
            .encode(x=_xs(4), y=y, color=color)
            .scale_color_log()
            .size(240, 180)
        )


def test_log_and_center_together_raise() raises:
    var y = List[Float64]()
    var color = List[Float64]()
    for i in range(4):
        y.append(Float64(i))
        color.append(Float64(i) + 1.0)
    with assert_raises(contains="not combinable"):
        _ = render(
            Plot()
            .mark_point()
            .encode(x=_xs(4), y=y, color=color)
            .scale_color_log()
            .scale_color_center(2.0)
            .size(240, 180)
        )


def test_a_log_chart_renders_and_differs_from_the_linear_one() raises:
    var y = List[Float64]()
    var color = List[Float64]()
    for i in range(6):
        y.append(Float64(i))
        color.append(10.0 ** Float64(i))
    var linear = render(
        Plot().mark_point().encode(x=_xs(6), y=y, color=color).size(240, 180)
    )
    var logged = render(
        Plot()
        .mark_point()
        .encode(x=_xs(6), y=y, color=color)
        .scale_color_log()
        .size(240, 180)
    )
    var diff = 0
    for py in range(linear.height):
        for px in range(linear.width):
            var a = linear.get_pixel(px, py)
            var b = logged.get_pixel(px, py)
            if a.r != b.r or a.g != b.g or a.b != b.b:
                diff += 1
    assert_true(diff > 20, "the log scale changed nothing on the canvas")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
