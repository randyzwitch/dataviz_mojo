"""Tests for color normalization (#370): `Plot.scale_color_domain()`,
`Plot.scale_color_center()`, and `shared_color_domain()`.

The expectations here are derived from the definitions, not from a
previous run. Two devices do most of the work:

- Colors are only ever asserted where no interpolation rounding is
  involved -- at the two domain ends and at the ramp's center, where the
  answer is a theme stop verbatim.
- The asymmetric arms of a centered ramp are checked against a *plain*
  `ColorScale` whose domain is that arm doubled. Centering is
  matplotlib's `TwoSlopeNorm`, so the lower arm of a scale centered at 0
  over `[-2, 10]` is exactly the ramp's lower half stretched over
  `[-2, 0]` -- which is what a plain scale over `[-2, 2]` does to the
  same values. Equality between the two is a statement about the
  definition that holds whatever canvas's stop interpolation rounds to.
"""

from canvas.color import Color
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from _test_helpers import _count_color
from dataviz.core.color_scale import (
    ColorScale,
    _ColorDomainOverride,
    _center_offset,
    _color_scale_for,
    shared_color_domain,
)
from dataviz.heatmap import heatmap
from dataviz.plot import Plot, render, render_svg
from dataviz.core.theme import Theme

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
    return d


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
