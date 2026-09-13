"""Discrete color thresholds (#370).

`n` boundaries make `n - 1` bands and every value in a band gets one flat
color, for when the question is "which category is this" rather than "how
much": soil pH bands, risk tiers, a legend with named ranges.

#370 names the thing that is easy to get wrong and asks for it to be
pinned: **which interval owns a value sitting exactly on a boundary.**
Intervals are lower-inclusive, `[b[i], b[i+1])`, with the last closed at
the top, which is matplotlib's `BoundaryNorm` rule. Three tests below are
about nothing else.

Colors are compared against a linear scale over `[0, 1]`, which indexes
the same ramp stops and so *is* the ramp by position. An earlier version
of the log tests used the sum of a color's channels as a stand-in for
position and got the wrong answer, because the default ramp's channel sum
is not monotonic.
"""

from std.testing import TestSuite, assert_raises, assert_true

from canvas.color import Color

from dataviz import Theme
from dataviz.core.color_scale import (
    ColorScale,
    _ColorDomainOverride,
    _color_scale_for,
)
from dataviz.plot import Plot, render


def _bounds() -> List[Float64]:
    # Three bands: [0, 10), [10, 20), [20, 30].
    var b = List[Float64]()
    b.append(0.0)
    b.append(10.0)
    b.append(20.0)
    b.append(30.0)
    return b^


def _banded() raises -> ColorScale:
    var d = _ColorDomainOverride()
    d.thresholds = _bounds()
    return _color_scale_for(Theme(), d^, 0.0, 30.0)


def _unit() raises -> ColorScale:
    return _color_scale_for(Theme(), _ColorDomainOverride(), 0.0, 1.0)


def _same(a: Color, b: Color) -> Bool:
    return a.r == b.r and a.g == b.g and a.b == b.b


def _rgb(c: Color) -> String:
    return "(" + String(c.r) + "," + String(c.g) + "," + String(c.b) + ")"


def _xs(n: Int) -> List[Float64]:
    var v = List[Float64]()
    for i in range(n):
        v.append(Float64(i))
    return v^


def test_every_value_in_a_band_gets_one_flat_color() raises:
    # The whole point: 1 and 9 are in the same band and must be
    # indistinguishable, where a continuous ramp would separate them.
    var scale = _banded()
    assert_true(
        _same(scale.color_at(1.0), scale.color_at(9.0)),
        "two values in [0, 10) got different colors: "
        + _rgb(scale.color_at(1.0))
        + " and "
        + _rgb(scale.color_at(9.0)),
    )
    var continuous = _color_scale_for(
        Theme(), _ColorDomainOverride(), 0.0, 30.0
    )
    assert_true(
        not _same(continuous.color_at(1.0), continuous.color_at(9.0)),
        "the continuous ramp also flattened them, so this proves nothing",
    )


def test_adjacent_bands_are_different_colors() raises:
    var scale = _banded()
    assert_true(
        not _same(scale.color_at(5.0), scale.color_at(15.0)),
        "the first two bands are the same color",
    )
    assert_true(
        not _same(scale.color_at(15.0), scale.color_at(25.0)),
        "the last two bands are the same color",
    )


def test_a_band_takes_its_color_from_its_own_middle() raises:
    # Three bands, so band k is sampled at (k + 0.5) / 3 along the ramp.
    # Pinned so a change to the sampling point has to be deliberate.
    var scale = _banded()
    var unit = _unit()
    for k in range(3):
        var value = Float64(k) * 10.0 + 5.0
        var want = unit.color_at((Float64(k) + 0.5) / 3.0)
        assert_true(
            _same(scale.color_at(value), want),
            "band "
            + String(k)
            + " is "
            + _rgb(scale.color_at(value))
            + " but the middle of its slice of the ramp is "
            + _rgb(want),
        )


def test_a_value_on_an_interior_boundary_belongs_to_the_band_above() raises:
    """#370's stated acceptance criterion: which interval owns an exact
    threshold.

    Intervals are lower-inclusive, so 10.0 is in `[10, 20)` and not in
    `[0, 10)`. Both halves are asserted, because "equals the upper band"
    alone would pass if every band were the same color.
    """
    var scale = _banded()
    assert_true(
        _same(scale.color_at(10.0), scale.color_at(15.0)),
        "10.0 did not land in the band above it",
    )
    assert_true(
        not _same(scale.color_at(10.0), scale.color_at(5.0)),
        "10.0 landed in the band below it",
    )


def test_the_domain_maximum_lands_in_the_top_band() raises:
    # The last interval is closed at the top, so 30.0 has somewhere to
    # go rather than falling off the end.
    var scale = _banded()
    assert_true(
        _same(scale.color_at(30.0), scale.color_at(25.0)),
        "the domain maximum fell outside every band",
    )


def test_values_outside_the_boundaries_clip_rather_than_raise() raises:
    # Clipping keeps one shared threshold list usable across facets
    # whose data ranges differ.
    var scale = _banded()
    assert_true(
        _same(scale.color_at(-5.0), scale.color_at(5.0)),
        "a value below the first boundary did not clip to the low band",
    )
    assert_true(
        _same(scale.color_at(99.0), scale.color_at(25.0)),
        "a value above the last boundary did not clip to the high band",
    )


def test_non_monotone_boundaries_raise() raises:
    var y = List[Float64]()
    var color = List[Float64]()
    for i in range(4):
        y.append(Float64(i))
        color.append(Float64(i))
    var bad = List[Float64]()
    bad.append(0.0)
    bad.append(20.0)
    bad.append(10.0)
    with assert_raises(contains="strictly increasing"):
        _ = render(
            Plot()
            .mark_point()
            .encode(x=_xs(4), y=y, color=color)
            .scale_color_thresholds(bad)
            .size(240, 180)
        )


def test_one_boundary_raises() raises:
    var y = List[Float64]()
    var color = List[Float64]()
    for i in range(4):
        y.append(Float64(i))
        color.append(Float64(i))
    var one = List[Float64]()
    one.append(0.0)
    with assert_raises(contains="at least two"):
        _ = render(
            Plot()
            .mark_point()
            .encode(x=_xs(4), y=y, color=color)
            .scale_color_thresholds(one)
            .size(240, 180)
        )


def test_thresholds_with_log_or_center_raise() raises:
    var y = List[Float64]()
    var color = List[Float64]()
    for i in range(4):
        y.append(Float64(i))
        color.append(Float64(i) + 1.0)
    with assert_raises(contains="nothing left to place"):
        _ = render(
            Plot()
            .mark_point()
            .encode(x=_xs(4), y=y, color=color)
            .scale_color_thresholds(_bounds())
            .scale_color_log()
            .size(240, 180)
        )
    with assert_raises(contains="nothing left to place"):
        _ = render(
            Plot()
            .mark_point()
            .encode(x=_xs(4), y=y, color=color)
            .scale_color_thresholds(_bounds())
            .scale_color_center(2.0)
            .size(240, 180)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
