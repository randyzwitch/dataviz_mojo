"""Color scales: normalization, the log color scale, threshold bands, and the key
drawn for a banded scale.

One module rather than 4: every test module pays the same dependency
compilation, so the suite is organized by family (#605).
"""

from std.math import cos, log10, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from canvas.color import Color
from dataviz import LegendPosition, Theme, contour, contourf
from dataviz.core.color_scale import (
    ColorScale,
    _ColorDomainOverride,
    _center_offset,
    _color_scale_for,
    shared_color_domain,
    symmetric_color_domain,
)
from dataviz.core.theme import Theme
from dataviz.grid.heatmap import heatmap
from dataviz.plot import Plot, render, render_svg
from _test_helpers import _attr_values, _count_color, _count_tag


# ==== from test_color_norm.mojo ====
# Tests for color normalization (#370): `Plot.scale_color_domain()`,
# `Plot.scale_color_center()`, and `shared_color_domain()`.
#
# The expectations here are derived from the definitions, not from a
# previous run. Two devices do most of the work:
#
# - Colors are only ever asserted where no interpolation rounding is
#   involved -- at the two domain ends and at the ramp's center, where the
#   answer is a theme stop verbatim.
# - The asymmetric arms of a centered ramp are checked against a *plain*
#   `ColorScale` whose domain is that arm doubled. Centering is
#   matplotlib's `TwoSlopeNorm`, so the lower arm of a scale centered at 0
#   over `[-2, 10]` is exactly the ramp's lower half stretched over
#   `[-2, 0]` -- which is what a plain scale over `[-2, 2]` does to the
#   same values. Equality between the two is a statement about the
#   definition that holds whatever canvas's stop interpolation rounds to.


comptime LOW = Color(10, 20, 30)
comptime MID = Color(40, 80, 120)
comptime HIGH = Color(200, 60, 90)


def _ramp_theme(show_legend: Bool = False) -> Theme:
    """A theme whose three color stops are far apart and unlike anything
    else a chart draws, so `_count_color` finding one in a canvas is
    evidence about the color scale and not about the axis furniture.
    """
    return Theme(
        color_scale_low=LOW,
        color_scale_mid=MID,
        color_scale_high=HIGH,
        show_legend=show_legend,
    )


def _override(min: Float64, max: Float64) -> _ColorDomainOverride:
    var d = _ColorDomainOverride()
    d.has = True
    d.min = min
    d.max = max
    return d^


def _text_y(svg: String, label: String) raises -> Int:
    """The `y` of the `<text>` element whose content is exactly `label`.

    The legend's labels are the only place a value appears as its own
    text node, so this locates a colorbar label's baseline without
    depending on how many elements the rest of the chart drew.
    """
    var needle = ">" + label + "</text>"
    var at = svg.find(needle)
    if at < 0:
        raise Error("no <text> element with content " + label)
    var head = String(svg[byte=0:at])
    var open_at = head.rfind("<text")
    if open_at < 0:
        raise Error("malformed <text> around " + label)
    var element = String(head[byte=open_at:])
    var key = ' y="'
    var k = element.find(key)
    if k < 0:
        raise Error("no y attribute on the <text> for " + label)
    var v = k + key.byte_length()
    var end = element.find('"', v)
    return Int(String(element[byte=v:end]))


def _assert_same_color(got: Color, want: Color, label: String) raises:
    assert_equal(got.r, want.r, label + " (red)")
    assert_equal(got.g, want.g, label + " (green)")
    assert_equal(got.b, want.b, label + " (blue)")


def test_center_offset_fixed_points() raises:
    """`_center_offset` is the piecewise-linear map that sends 0 to 0,
    0.5 to `t`, and 1 to 1. Those three are the definition; the two
    midpoints below are read straight off it (a quarter of the way up
    each arm).
    """
    var centers: List[Float64] = [0.1, 0.25, 0.5, 0.9]
    for t in centers:
        assert_equal(_center_offset(0.0, t), 0.0, "0 stays at 0")
        assert_equal(_center_offset(0.5, t), t, "0.5 lands on the center")
        assert_equal(_center_offset(1.0, t), 1.0, "1 stays at 1")

    # t = 0.25: the lower arm compresses [0, 0.5] into [0, 0.25], so
    # 0.25 (half way up it) lands at 0.125; the upper arm stretches
    # [0.5, 1] over [0.25, 1], so 0.75 lands at 0.25 + 0.375 = 0.625.
    # Quarters rather than tenths so both sides are exact in binary and
    # the assertion is about the map, not about floating point.
    assert_equal(_center_offset(0.25, 0.25), 0.125, "lower arm midpoint")
    assert_equal(_center_offset(0.75, 0.25), 0.625, "upper arm midpoint")

    # t = 0.5 is the uncentered ramp: every offset stays put.
    assert_equal(_center_offset(0.25, 0.5), 0.25, "t=0.5 is the identity")
    assert_equal(_center_offset(0.75, 0.5), 0.75, "t=0.5 is the identity")


def test_no_override_uses_the_data_limits() raises:
    """With nothing set, `_color_scale_for` hands back exactly the limits
    the mark derived -- the behavior every mark had before #370.
    """
    var theme = _ramp_theme()
    var scale = _color_scale_for(theme, _ColorDomainOverride(), -3.0, 7.0)
    assert_equal(scale.domain_min, -3.0, "min is the data's")
    assert_equal(scale.domain_max, 7.0, "max is the data's")
    assert_true(not scale.has_center, "no center was asked for")


def test_override_replaces_the_data_limits() raises:
    """The override wins over whatever the mark derived, and the derived
    limits leave no trace.
    """
    var theme = _ramp_theme()
    var scale = _color_scale_for(theme, _override(0.0, 20.0), 0.0, 10.0)
    assert_equal(scale.domain_min, 0.0, "min is the override's")
    assert_equal(scale.domain_max, 20.0, "max is the override's")
    # 10 is the data's max but the domain's midpoint, so it gets the
    # middle stop verbatim rather than the high one.
    _assert_same_color(scale.color_at(10.0), MID, "midpoint of the override")
    _assert_same_color(scale.color_at(20.0), HIGH, "top of the override")


def test_shared_override_makes_two_charts_agree() raises:
    """The point of the whole feature: two marks with different data and
    one shared domain map equal values to equal colors, and without it
    they do not.
    """
    var theme = _ramp_theme()
    var shared = _override(0.0, 20.0)
    var a = _color_scale_for(theme, shared, 0.0, 10.0)
    var b = _color_scale_for(theme, shared, 0.0, 20.0)
    var probes: List[Float64] = [0.0, 5.0, 10.0, 15.0, 20.0]
    for v in probes:
        _assert_same_color(
            a.color_at(v), b.color_at(v), "shared domain at " + String(v)
        )

    # Same two data ranges, no override: 10 is the top of one scale and
    # the middle of the other. This is the bug #370 describes, and it is
    # what makes the assertions above worth making.
    var a_own = _color_scale_for(theme, _ColorDomainOverride(), 0.0, 10.0)
    var b_own = _color_scale_for(theme, _ColorDomainOverride(), 0.0, 20.0)
    _assert_same_color(a_own.color_at(10.0), HIGH, "10 tops its own scale")
    _assert_same_color(b_own.color_at(10.0), MID, "10 centers its own scale")


def test_centered_ramp_pins_the_center_color() raises:
    """A ramp centered at 0 over an asymmetric domain puts the middle
    stop on 0 and leaves both ends alone.
    """
    var theme = _ramp_theme()
    var d = _override(-2.0, 10.0)
    d.has_center = True
    d.center = 0.0
    var scale = _color_scale_for(theme, d, -2.0, 10.0)

    assert_equal(scale.domain_min, -2.0, "centering does not move the ends")
    assert_equal(scale.domain_max, 10.0, "centering does not move the ends")
    assert_true(scale.has_center, "the scale records its center")
    assert_equal(scale.center, 0.0, "the center is the one asked for")

    _assert_same_color(scale.color_at(-2.0), LOW, "low end")
    _assert_same_color(scale.color_at(0.0), MID, "center")
    _assert_same_color(scale.color_at(10.0), HIGH, "high end")

    # The numeric midpoint (4.0) is no longer the neutral color; without
    # centering it would be exactly MID.
    var uncentered = _color_scale_for(theme, _override(-2.0, 10.0), 0.0, 1.0)
    _assert_same_color(
        uncentered.color_at(4.0), MID, "uncentered midpoint is neutral"
    )
    var at_four = scale.color_at(4.0)
    assert_true(
        not (at_four.r == MID.r and at_four.g == MID.g and at_four.b == MID.b),
        "centering moves the neutral color off the numeric midpoint",
    )


def test_centered_arms_match_two_slope_norm() raises:
    """Each arm of a centered ramp is that half of the ramp stretched
    over the arm, which is matplotlib's `TwoSlopeNorm`. The lower arm of
    `[-2, 10]` centered at 0 covers `[-2, 0]` with the ramp's lower half,
    exactly as a plain scale over `[-2, 2]` does; the upper arm covers
    `[0, 10]` with the upper half, as a plain scale over `[-10, 10]`
    does.
    """
    var theme = _ramp_theme()
    var d = _override(-2.0, 10.0)
    d.has_center = True
    d.center = 0.0
    var scale = _color_scale_for(theme, d, -2.0, 10.0)

    var lower_equivalent = ColorScale.from_theme(theme, -2.0, 2.0)
    var lower_probes: List[Float64] = [-2.0, -1.5, -1.0, -0.5]
    for v in lower_probes:
        _assert_same_color(
            scale.color_at(v),
            lower_equivalent.color_at(v),
            "lower arm at " + String(v),
        )

    var upper_equivalent = ColorScale.from_theme(theme, -10.0, 10.0)
    var upper_probes: List[Float64] = [2.5, 5.0, 7.5, 10.0]
    for v in upper_probes:
        _assert_same_color(
            scale.color_at(v),
            upper_equivalent.color_at(v),
            "upper arm at " + String(v),
        )


def test_centered_ramp_without_an_explicit_domain() raises:
    """A center on its own re-places the ramp inside the data's own
    limits; no `scale_color_domain()` is needed for the common case.
    """
    var theme = _ramp_theme()
    var d = _ColorDomainOverride()
    d.has_center = True
    d.center = 0.0
    var scale = _color_scale_for(theme, d, -5.0, 15.0)
    assert_equal(scale.domain_min, -5.0, "limits still come from the data")
    assert_equal(scale.domain_max, 15.0, "limits still come from the data")
    _assert_same_color(scale.color_at(0.0), MID, "center is neutral")


def test_center_outside_the_domain_raises() raises:
    """The domain is not quietly widened to swallow the center: a chart
    that did that would get different end colors than the one beside it.
    """
    var theme = _ramp_theme()
    var d = _ColorDomainOverride()
    d.has_center = True
    d.center = 0.0
    with assert_raises(contains="strictly inside the color domain"):
        _ = _color_scale_for(theme, d, 1.0, 9.0)
    with assert_raises(contains="strictly inside the color domain"):
        _ = _color_scale_for(theme, d, -9.0, -1.0)

    # An endpoint is outside too -- one arm would have no width at all.
    var at_end = _ColorDomainOverride()
    at_end.has_center = True
    at_end.center = 0.0
    with assert_raises(contains="strictly inside the color domain"):
        _ = _color_scale_for(theme, at_end, 0.0, 10.0)


def test_inverted_domain_raises() raises:
    var theme = _ramp_theme()
    with assert_raises(contains="min must be less than max"):
        _ = _color_scale_for(theme, _override(10.0, 1.0), 0.0, 1.0)
    with assert_raises(contains="min must be less than max"):
        _ = _color_scale_for(theme, _override(4.0, 4.0), 0.0, 1.0)


def test_heatmap_honors_the_override() raises:
    """The wiring test: a mark must color through the override, not
    through its own data's limits.

    With the data's own limits the largest value gets the high stop.
    Doubling the domain moves it to the middle stop, so the high stop
    should not be painted anywhere at all.
    """
    var xs: List[String] = ["a", "b", "c"]
    var ys: List[String] = ["r", "r", "r"]
    var values: List[Float64] = [0.0, 5.0, 10.0]

    var own = render(heatmap(xs, ys, values, theme=_ramp_theme()))
    assert_true(
        _count_color(own, HIGH) > 0,
        "without an override the data max reaches the high stop",
    )

    var pinned = render(
        heatmap(xs, ys, values, theme=_ramp_theme()).scale_color_domain(
            0.0, 20.0
        )
    )
    assert_equal(
        _count_color(pinned, HIGH),
        0,
        "with a domain of [0, 20] nothing reaches the high stop",
    )
    assert_true(
        _count_color(pinned, MID) > 0,
        "10 is the midpoint of [0, 20] and gets the middle stop",
    )


def test_heatmap_center_moves_the_neutral_cell() raises:
    """A centered heatmap puts the neutral color on the centered value,
    not on the numeric midpoint of the data.
    """
    var xs: List[String] = ["a", "b", "c"]
    var ys: List[String] = ["r", "r", "r"]
    # Numeric midpoint 4.0; the cell at 0.0 is the one that should end up
    # neutral once the ramp is centered there.
    var values: List[Float64] = [-2.0, 0.0, 10.0]

    var centered = render(
        heatmap(xs, ys, values, theme=_ramp_theme()).scale_color_center(0.0)
    )
    assert_true(
        _count_color(centered, MID) > 0,
        "the zero cell is painted with the middle stop",
    )

    var plain = render(heatmap(xs, ys, values, theme=_ramp_theme()))
    assert_equal(
        _count_color(plain, MID),
        0,
        "uncentered, no cell sits on the numeric midpoint of [-2, 10]",
    )


def test_legend_labels_follow_the_override() raises:
    """The colorbar has to agree with the mapping the mark used, so its
    labels come from the overridden domain.
    """
    var xs: List[String] = ["a", "b"]
    var ys: List[String] = ["r", "r"]
    var values: List[Float64] = [0.0, 10.0]

    var own = render_svg(
        heatmap(xs, ys, values, theme=_ramp_theme(True))
    ).to_string()
    assert_true(">10.0<" in own, "the data's own max labels the bar")

    var pinned = render_svg(
        heatmap(xs, ys, values, theme=_ramp_theme(True)).scale_color_domain(
            0.0, 20.0
        )
    ).to_string()
    assert_true(">20.0<" in pinned, "the override's max labels the bar")
    assert_true(
        not (">10.0<" in pinned),
        "the data's own max is gone from the legend",
    )


def test_legend_labels_the_center() raises:
    """With asymmetric arms the two end labels cannot say where the
    neutral color sits, so a centered scale gets a third label.
    """
    var xs: List[String] = ["a", "b", "c"]
    var ys: List[String] = ["r", "r", "r"]
    var values: List[Float64] = [-2.0, 1.0, 10.0]

    var cells = _cells()
    var plain = render_svg(
        heatmap(xs, ys, values, theme=_ramp_theme(True))
    ).to_string()
    assert_true(not (">0.0<" in plain), "no center label without centering")

    var centered = render_svg(
        heatmap(xs, ys, values, theme=_ramp_theme(True)).scale_color_center(0.0)
    ).to_string()
    assert_true(">0.0<" in centered, "the center value labels the bar")
    assert_true(">-2.0<" in centered, "the low end is still labeled")
    assert_true(">10.0<" in centered, "the high end is still labeled")

    # And it sits where the ramp actually turns neutral, which is what
    # makes the colorbar agree with the mark rather than merely mention
    # the number. The bar runs high at the top, so with a domain of
    # [-2, 10] centered at 0 the center is t = 2/12 of the way up and
    # therefore 1 - t of the way down from the top edge. The two end
    # labels sit on the bar's two edges, so their baselines give its
    # height without assuming a theme's dimensions.
    var top_y = _text_y(centered, "10.0")
    var bottom_y = _text_y(centered, "-2.0")
    var center_y = _text_y(centered, "0.0")
    var bar_height = bottom_y - top_y
    var t = 2.0 / 12.0
    assert_equal(
        center_y,
        top_y + Int((1.0 - t) * Float64(bar_height)),
        "the center label sits at the ramp's neutral point",
    )


def test_unsupported_mark_raises() raises:
    """An override a mark would ignore is refused rather than accepted
    and dropped -- an ignored setting is the failure this API exists to
    prevent.
    """
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var bar = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .scale_color_domain(0.0, 10.0)
    )
    with assert_raises(contains="no continuous color channel"):
        _ = render(bar)

    # Mark.POINT does support it, but only with a numeric color channel.
    var no_color = (
        Plot().mark_point().encode(x=vals, y=vals).scale_color_center(0.0)
    )
    with assert_raises(contains="no continuous color channel"):
        _ = render(no_color)


def test_point_color_channel_honors_the_override() raises:
    """`Plot.encode(color=...)`'s continuous channel goes through the
    same resolver, so a scatter's colors pin the same way a grid mark's
    do.
    """
    var xs: List[Float64] = [0.0, 1.0, 2.0]
    var ys: List[Float64] = [0.0, 1.0, 2.0]
    var colors: List[Float64] = [0.0, 5.0, 10.0]

    var own = render(
        Plot()
        .mark_point()
        .encode(x=xs, y=ys, color=colors)
        .theme(_ramp_theme())
    )
    assert_true(_count_color(own, HIGH) > 0, "10 tops the point's own scale")

    var pinned = render(
        Plot()
        .mark_point()
        .encode(x=xs, y=ys, color=colors)
        .theme(_ramp_theme())
        .scale_color_domain(0.0, 20.0)
    )
    assert_equal(_count_color(pinned, HIGH), 0, "nothing reaches the high stop")


def test_shared_color_domain_pools_flat_lists() raises:
    var a: List[Float64] = [1.0, 4.0]
    var b: List[Float64] = [-2.0, 3.0]
    var empty = List[Float64]()
    var samples: List[List[Float64]] = [a.copy(), b.copy(), empty^]
    var domain = shared_color_domain(samples)
    assert_equal(domain.min, -2.0, "smallest value anywhere")
    assert_equal(domain.max, 4.0, "largest value anywhere")


def test_shared_color_domain_pools_grids() raises:
    var g1: List[List[Float64]] = [[1.0, 2.0], [3.0, 4.0]]
    var g2: List[List[Float64]] = [[-5.0, 0.0], [0.5, 1.5]]
    var grids: List[List[List[Float64]]] = [g1.copy(), g2.copy()]
    var domain = shared_color_domain(grids)
    assert_equal(domain.min, -5.0, "smallest value in either grid")
    assert_equal(domain.max, 4.0, "largest value in either grid")


def test_shared_color_domain_rejects_empty_and_non_finite() raises:
    var none = List[List[Float64]]()
    with assert_raises(contains="at least one value"):
        _ = shared_color_domain(none)

    var all_empty: List[List[Float64]] = [
        List[Float64](),
        List[Float64](),
    ]
    with assert_raises(contains="at least one value"):
        _ = shared_color_domain(all_empty)

    var no_grids = List[List[List[Float64]]]()
    with assert_raises(contains="at least one value"):
        _ = shared_color_domain(no_grids)

    var nan: List[List[Float64]] = [[0.0, 1.0], [2.0, Float64("nan")]]
    with assert_raises(contains="must be finite"):
        _ = shared_color_domain(nan)


def test_shared_color_domain_drives_two_heatmaps() raises:
    """End to end: pooled limits fed to two charts make the same value
    the same color in both, which is what `shared_bin_edges()` does for
    a pair of histograms.
    """
    var xs: List[String] = ["a", "b"]
    var ys: List[String] = ["r", "r"]
    var left: List[Float64] = [0.0, 10.0]
    var right: List[Float64] = [10.0, 20.0]
    var samples: List[List[Float64]] = [left.copy(), right.copy()]
    var domain = shared_color_domain(samples)
    assert_equal(domain.max, 20.0, "pooled max")

    var lc = render(
        heatmap(xs, ys, left, theme=_ramp_theme()).scale_color_domain(
            domain.min, domain.max
        )
    )
    var rc = render(
        heatmap(xs, ys, right, theme=_ramp_theme()).scale_color_domain(
            domain.min, domain.max
        )
    )
    # 10 is the midpoint of the pooled domain in both charts.
    assert_true(_count_color(lc, MID) > 0, "left chart's 10 is neutral")
    assert_true(_count_color(rc, MID) > 0, "right chart's 10 is neutral")
    assert_equal(_count_color(lc, HIGH), 0, "left chart never reaches high")
    assert_true(_count_color(rc, HIGH) > 0, "right chart's 20 does")


# ==== from test_color_log_scale.mojo ====
# Logarithmic color normalization (#370).
#
# A linear ramp cannot resolve values spread over orders of magnitude: on a
# 1-to-10,000 domain everything below 1,000 sits in the first tenth of the
# ramp and reads as one color. `Plot.scale_color_log()` normalizes by
# `log10` instead, so equal *ratios* get equal color distance.
#
# #370's acceptance criterion for this part is "log-spaced values have
# evenly spaced normalized positions", which is what
# `test_log_spaced_values_are_evenly_spaced_in_color` checks directly
# rather than by eye.
#
# This is the one piece of #370 not entangled with missing-data handling
# (#367, on hold): out-of-range and missing colors have to wait for what a
# gap means, and a log domain does not.


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


# ==== from test_color_thresholds.mojo ====
# Discrete color thresholds (#370).
#
# `n` boundaries make `n - 1` bands and every value in a band gets one flat
# color, for when the question is "which category is this" rather than "how
# much": soil pH bands, risk tiers, a legend with named ranges.
#
# #370 names the thing that is easy to get wrong and asks for it to be
# pinned: **which interval owns a value sitting exactly on a boundary.**
# Intervals are lower-inclusive, `[b[i], b[i+1])`, with the last closed at
# the top, which is matplotlib's `BoundaryNorm` rule. Three tests below are
# about nothing else.
#
# Colors are compared against a linear scale over `[0, 1]`, which indexes
# the same ramp stops and so *is* the ramp by position. An earlier version
# of the log tests used the sum of a color's channels as a stand-in for
# position and got the wrong answer, because the default ramp's channel sum
# is not monotonic.


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


def _unit_color_thresholds() raises -> ColorScale:
    return _color_scale_for(Theme(), _ColorDomainOverride(), 0.0, 1.0)


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
    var unit = _unit_color_thresholds()
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


# ==== from test_color_legend.mojo ====
# Tests for the color keys on the contour, tricontour and tripcolor
# marks (#525).
#
# `Mark.CONTOUR` and `Mark.CONTOURF` built a `ColorScale` and painted with
# it while drawing no key at all, so the chart showed colors the reader had
# nothing to read them against. The discriminator used throughout is the
# count of `<text>` elements with the legend on against off: the axis
# furniture is identical either way, so the difference is exactly the
# key's rows.
#
# `Mark.TRICONTOUR`, `TRICONTOURF` and `TRIPCOLOR` have the same gap and
# are not covered here; they are layerable, and a standalone key without a
# layered one breaks the invariant that a lone layer matches the
# standalone chart. See #525.


def _grid() -> List[List[Float64]]:
    var z = List[List[Float64]]()
    for r in range(16):
        var row = List[Float64]()
        for c in range(20):
            row.append(sin(Float64(c) / 5.0) * cos(Float64(r) / 4.0) * 10.0)
        z.append(row^)
    return z^


def _texts(p: Plot) raises -> Int:
    return _count_tag(render_svg(p).to_string(), "text")


def _on() -> Theme:
    return Theme(show_gridlines=False)


def _off() -> Theme:
    return Theme(show_gridlines=False, show_legend=False)


def test_both_contour_marks_draw_a_key_they_previously_did_not() raises:
    # The axis furniture is the same either way, so the delta is the
    # key. Before #525 each of these was zero.
    var z = _grid()
    var levels = 5

    var d_contour = _texts(
        contour(z, level_count=levels, theme=_on(), width=460, height=320)
    ) - _texts(
        contour(z, level_count=levels, theme=_off(), width=460, height=320)
    )
    var d_contourf = _texts(
        contourf(z, level_count=levels, theme=_on(), width=460, height=320)
    ) - _texts(
        contourf(z, level_count=levels, theme=_off(), width=460, height=320)
    )
    # One row per level: the levels are discrete by construction, so the
    # key is a swatch each rather than a gradient bar.
    assert_equal(d_contour, levels, "contour draws one key row per level")
    assert_equal(d_contourf, levels, "contourf draws one key row per level")


def test_the_key_rows_are_ordered_high_to_low() raises:
    # The *values* descend, not merely the row positions -- rows always
    # run down the page whatever order they were handed in, so asserting
    # their y-coordinates proves nothing. This reads the labels.
    var s = render_svg(
        contourf(_grid(), level_count=4, theme=_on(), width=460, height=320)
    ).to_string()
    var labels = List[String]()
    var at = s.find("<text")
    while at >= 0:
        var gt = s.find(">", at)
        var close = s.find("</text>", gt)
        labels.append(String(s[byte = gt + 1 : close]))
        at = s.find("<text", at + 1)
    assert_true(len(labels) >= 4, "the key drew rows")
    # The key's rows are the last four text elements.
    var n = len(labels)
    var previous = Float64(labels[n - 4])
    for i in range(n - 3, n):
        var value = Float64(labels[i])
        assert_true(
            value < previous,
            "key rows descend in value -- got "
            + labels[i]
            + " after "
            + labels[i - 1],
        )
        previous = value


def test_a_key_swatch_is_the_color_of_the_band_it_keys() raises:
    # The invariant that makes the key worth drawing, and the one that
    # catches a key built from the data's own limits while the bands
    # honor a `scale_color_domain()` override: every swatch color must
    # be a color actually painted on the chart.
    var pinned = render_svg(
        contourf(
            _grid(), level_count=4, theme=_on(), width=460, height=320
        ).scale_color_domain(-40.0, 40.0)
    ).to_string()
    var band_fills = _attr_values(pinned, "path", "fill")
    var swatch_fills = _attr_values(pinned, "rect", "fill")
    assert_true(len(band_fills) > 0, "the bands drew")
    # The key's swatches are the last four rects: the key is drawn after
    # the chart. The others are the background and the plot area, which
    # can share a fill with a band by coincidence.
    assert_true(len(swatch_fills) >= 4, "the key drew swatches")
    var matched = 0
    for i in range(len(swatch_fills) - 4, len(swatch_fills)):
        for band in band_fills:
            if swatch_fills[i] == band:
                matched += 1
                break
    assert_equal(
        matched,
        4,
        "each of the four swatches is a color the chart paints -- got "
        + String(matched)
        + " of 4",
    )


def test_turning_the_legend_off_removes_the_key_entirely() raises:
    var z = _grid()
    var s = render_svg(
        contourf(z, level_count=5, theme=_off(), width=460, height=320)
    ).to_string()
    var on = render_svg(
        contourf(z, level_count=5, theme=_on(), width=460, height=320)
    ).to_string()
    assert_true(
        _count_tag(on, "rect") > _count_tag(s, "rect"),
        "the key's swatches are rects, and they go with the legend",
    )


# ==== out-of-range colors and a symmetric shared domain (#370) ====
# `Plot.scale_color_under()`/`scale_color_over()` give a value outside
# the domain its own color instead of the ramp's end, and
# `symmetric_color_domain()` balances a diverging ramp's two arms.


comptime UNDER = Color(250, 0, 250)
comptime OVER = Color(0, 250, 250)


def _out_of_range(
    min: Float64,
    max: Float64,
    under: Bool = True,
    over: Bool = True,
) -> _ColorDomainOverride:
    var d = _override(min, max)
    d.has_under = under
    d.under = UNDER
    d.has_over = over
    d.over = OVER
    return d^


def test_a_value_outside_the_domain_takes_its_own_color() raises:
    var scale = _color_scale_for(
        _ramp_theme(), _out_of_range(0.0, 10.0), 0.0, 10.0
    )
    _assert_same_color(scale.color_at(-0.5), UNDER, "below the domain")
    _assert_same_color(scale.color_at(-1000.0), UNDER, "far below")
    _assert_same_color(scale.color_at(10.5), OVER, "above the domain")
    _assert_same_color(scale.color_at(1000.0), OVER, "far above")


def test_the_domain_ends_belong_to_the_ramp() raises:
    # The boundary rule, stated once: the ends are in range, so they
    # keep the ramp's own colors and only what is strictly outside is
    # out.
    var scale = _color_scale_for(
        _ramp_theme(), _out_of_range(0.0, 10.0), 0.0, 10.0
    )
    _assert_same_color(scale.color_at(0.0), LOW, "the minimum is in range")
    _assert_same_color(scale.color_at(10.0), HIGH, "so is the maximum")


def test_each_out_of_range_color_stands_alone() raises:
    var only_under = _color_scale_for(
        _ramp_theme(), _out_of_range(0.0, 10.0, over=False), 0.0, 10.0
    )
    _assert_same_color(only_under.color_at(-1.0), UNDER, "under is set")
    _assert_same_color(
        only_under.color_at(11.0), HIGH, "over is not, so it still clamps"
    )
    var only_over = _color_scale_for(
        _ramp_theme(), _out_of_range(0.0, 10.0, under=False), 0.0, 10.0
    )
    _assert_same_color(only_over.color_at(11.0), OVER, "over is set")
    _assert_same_color(only_over.color_at(-1.0), LOW, "under is not")


def test_without_them_an_out_of_range_value_still_clamps() raises:
    # The behavior every chart had before this existed, pinned so the
    # default cannot drift.
    var scale = _color_scale_for(_ramp_theme(), _override(0.0, 10.0), 0.0, 10.0)
    _assert_same_color(scale.color_at(-5.0), LOW, "clamps to the low end")
    _assert_same_color(scale.color_at(15.0), HIGH, "and to the high end")


def test_out_of_range_colors_reach_a_banded_ramp() raises:
    # With thresholds the band edges are the range, not the domain.
    var d = _out_of_range(0.0, 10.0)
    var edges: List[Float64] = [2.0, 5.0, 8.0]
    d.thresholds = edges.copy()
    var scale = _color_scale_for(_ramp_theme(), d, 0.0, 10.0)
    _assert_same_color(scale.color_at(1.0), UNDER, "below the first edge")
    _assert_same_color(scale.color_at(9.0), OVER, "above the last edge")
    _assert_same_color(
        scale.color_at(8.0), scale.color_at(7.9), "the last edge is in range"
    )


def test_out_of_range_colors_reach_a_log_ramp() raises:
    var d = _out_of_range(1.0, 1000.0)
    d.log = True
    var scale = _color_scale_for(_ramp_theme(), d, 1.0, 1000.0)
    _assert_same_color(scale.color_at(0.5), UNDER, "below a log domain")
    _assert_same_color(scale.color_at(5000.0), OVER, "above it")
    _assert_same_color(scale.color_at(1.0), LOW, "the ends are still in range")
    _assert_same_color(scale.color_at(1000.0), HIGH, "and the high end")


def _floats(svg: String, attr: String) raises -> List[Float64]:
    """Every `<rect>`'s `attr`, in document order."""
    var out = List[Float64]()
    for v in _attr_values(svg, "rect", attr):
        out.append(Float64(v))
    return out^


def _bar_extent(svg: String) raises -> Tuple[Float64, Float64]:
    """The color bar's top and bottom, blocks included.

    The ramp is the one rect painted with a gradient; the out-of-range
    blocks, when there are any, are the rects sharing its column and
    sitting flush against its two ends. Found by geometry rather than by
    document order, which the SVG backend is free to choose (it emits
    gradient fills last).
    """
    var xs = _floats(svg, "x")
    var ys = _floats(svg, "y")
    var ws = _floats(svg, "width")
    var hs = _floats(svg, "height")
    var fills = _attr_values(svg, "rect", "fill")
    var ramp = -1
    for i in range(len(fills)):
        if fills[i].startswith("url("):
            if ramp >= 0:
                raise Error("more than one gradient rect")
            ramp = i
    if ramp < 0:
        raise Error("no gradient rect in the document")
    var top = ys[ramp]
    var bottom = ys[ramp] + hs[ramp]
    for i in range(len(ys)):
        if i == ramp or xs[i] != xs[ramp] or ws[i] != ws[ramp]:
            continue
        if ys[i] + hs[i] == ys[ramp]:
            top = ys[i]
        if ys[i] == ys[ramp] + hs[ramp]:
            bottom = ys[i] + hs[i]
    return (top, bottom)


def _cells() raises -> Tuple[List[String], List[String], List[Float64]]:
    """A 4x4 heatmap in the long form `heatmap()` takes: one x, one y and
    one value per cell, the values running 0 to 15.
    """
    var xs = List[String]()
    var ys = List[String]()
    var vals = List[Float64]()
    for r in range(4):
        for c in range(4):
            xs.append(String(c))
            ys.append(String(r))
            vals.append(Float64(r * 4 + c))
    return (xs^, ys^, vals^)


def test_the_color_bar_shows_the_out_of_range_colors() raises:
    # A legend that did not show them would disagree with the marks for
    # exactly the values the colors exist to call out.
    var cells = _cells()
    var c = render(
        heatmap(
            cells[0], cells[1], cells[2], theme=_ramp_theme(show_legend=True)
        )
        .scale_color_domain(4.0, 11.0)
        .scale_color_under(UNDER)
        .scale_color_over(OVER)
    )
    assert_true(_count_color(c, UNDER) > 0, "the under block is drawn")
    assert_true(_count_color(c, OVER) > 0, "and the over block")


def test_the_color_bar_keeps_its_footprint() raises:
    # The blocks take a slice off the ramp rather than extending the
    # bar, so a legend with them reserves exactly the room one without
    # them does and everything stacked below stays put.
    var cells = _cells()
    var plain = render_svg(
        heatmap(
            cells[0], cells[1], cells[2], theme=_ramp_theme(show_legend=True)
        ).scale_color_domain(4.0, 11.0)
    ).to_string()
    var marked = render_svg(
        heatmap(
            cells[0], cells[1], cells[2], theme=_ramp_theme(show_legend=True)
        )
        .scale_color_domain(4.0, 11.0)
        .scale_color_under(UNDER)
        .scale_color_over(OVER)
    ).to_string()
    var a = _bar_extent(plain)
    var b = _bar_extent(marked)
    assert_equal(b[0], a[0], "the bar starts where it did")
    assert_equal(b[1], a[1], "and ends where it did")
    # And the ramp itself gave up the room, which is what makes that
    # possible.
    var a_h = _floats(plain, "height")
    var b_h = _floats(marked, "height")
    var a_f = _attr_values(plain, "rect", "fill")
    var b_f = _attr_values(marked, "rect", "fill")
    var a_ramp = 0.0
    for i in range(len(a_f)):
        if a_f[i].startswith("url("):
            a_ramp = a_h[i]
    var b_ramp = 0.0
    for i in range(len(b_f)):
        if b_f[i].startswith("url("):
            b_ramp = b_h[i]
    assert_true(
        b_ramp < a_ramp,
        "the ramp is shorter by the two blocks: "
        + String(b_ramp)
        + " against "
        + String(a_ramp),
    )


def test_a_row_legend_shows_them_too() raises:
    # The row form lays its bar out along x with the labels inline, so
    # it slices the two ends rather than the top and bottom. Same
    # promise, other axis.
    var cells = _cells()
    var theme = Theme(
        color_scale_low=LOW,
        color_scale_mid=MID,
        color_scale_high=HIGH,
        show_legend=True,
        legend_position=LegendPosition.BOTTOM,
    )
    var c = render(
        heatmap(cells[0], cells[1], cells[2], theme=theme)
        .scale_color_domain(4.0, 11.0)
        .scale_color_under(UNDER)
        .scale_color_over(OVER)
    )
    assert_true(_count_color(c, UNDER) > 0, "the under block is drawn")
    assert_true(_count_color(c, OVER) > 0, "and the over block")


def test_symmetric_color_domain_balances_the_arms() raises:
    var samples = List[List[Float64]]()
    var a: List[Float64] = [-2.0, 0.0, 3.0]
    var b: List[Float64] = [1.0, 8.0]
    samples.append(a^)
    samples.append(b^)
    var d = symmetric_color_domain(samples)
    assert_equal(d.min, -8.0, "the far arm sets the radius")
    assert_equal(d.max, 8.0)
    # Which is the point: equal distances either side of the center are
    # now equally intense, where the data's own limits would have made
    # -2 the deepest low and +8 the deepest high.
    var lopsided = shared_color_domain(samples)
    assert_equal(lopsided.min, -2.0, "the plain shared domain is lopsided")
    assert_equal(lopsided.max, 8.0)


def test_symmetric_color_domain_takes_the_center_it_is_given() raises:
    var samples = List[List[Float64]]()
    var a: List[Float64] = [10.0, 14.0, 19.0]
    samples.append(a^)
    var d = symmetric_color_domain(samples, 15.0)
    assert_equal(d.min, 10.0, "5 below a center of 15")
    assert_equal(d.max, 20.0, "and 5 above it")


def test_a_symmetric_domain_on_data_that_is_all_center_still_has_width() raises:
    # A zero-span domain colors everything the ramp's low end, which
    # says nothing at all; a unit of width at least keeps the center
    # neutral.
    var samples = List[List[Float64]]()
    var a: List[Float64] = [0.0, 0.0, 0.0]
    samples.append(a^)
    var d = symmetric_color_domain(samples)
    assert_true(d.max > d.min, "the domain has width")
    assert_equal(d.min, -1.0)
    assert_equal(d.max, 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
