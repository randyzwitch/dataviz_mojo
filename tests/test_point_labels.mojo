"""Tests for `Plot.encode()`'s `labels` channel on `Mark.POINT`/
`EFFECT_SCATTER`: each point's own text drawn centered directly above
it -- hand-derived (cross-checked against a real render) label
placement, the per-row `""` opt-out, the default-no-labels case, and
every raise path (a length mismatch, an unsupported mark).
"""

from std.testing import assert_true, assert_raises, TestSuite

from dataviz.plot import Plot, render_svg
from dataviz.theme import Theme


def test_render_svg_point_labels_match_hand_derived_positions() raises:
    # x=[1,2,3], y=[10,20,30], canvas 400x300, default theme (this
    # package's usual default-margin frame for this size) -- plot rect
    # x:[60,380] y:[20,250]. Points at (75,240), (220,135), (365,30)
    # (this package's usual 5%-padded LinearScale domain for this
    # data/range). labels=["a", "", "c"]: "b" deliberately omitted (the
    # per-row "" opt-out) to prove it draws no label for that one point
    # while its neighbors still get theirs.
    #
    # Label baseline sits label_gap(4) above the point's own top edge
    # (py - radius(4) - 4): "a" at (75, 240-4-4=232), "c" at
    # (365, 30-4-4=22).
    # Every position independently re-derived via python3 and cross-
    # checked against the actual rendered SVG.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 20.0, 30.0]
    var labels: List[String] = ["a", "", "c"]
    var plot = Plot().mark_point().encode(x=x, y=y, labels=labels).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="75" y="232" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">a</text>' in s,
        "first point's label",
    )
    assert_true(
        '<text x="365" y="22" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">c</text>' in s,
        "third point's label",
    )
    assert_true('>b<' not in s, "the middle point's \"\" entry draws no label at all")


def test_render_svg_point_draws_no_labels_by_default() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 20.0, 30.0]
    var plot = Plot().mark_point().encode(x=x, y=y).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('text-anchor="middle">a</text>' not in s, "no point labels without encode()'s labels")


def test_render_svg_effect_scatter_supports_labels() raises:
    # Same frame convention as the Mark.POINT test above, 2 points --
    # EFFECT_SCATTER's extra halo circle doesn't change the label's own
    # placement, which still anchors off the inner point circle's
    # radius, not the halo's.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var labels: List[String] = ["p", "q"]
    var plot = Plot().mark_effect_scatter().encode(x=x, y=y, labels=labels).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="75" y="232" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">p</text>' in s,
        "first point's label",
    )
    assert_true(
        '<text x="365" y="22" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">q</text>' in s,
        "second point's label",
    )


def test_encode_raises_on_labels_length_mismatch() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var labels: List[String] = ["only one"]
    with assert_raises():
        var plot = Plot().mark_point().encode(x=x, y=y, labels=labels).size(400, 300)
        _ = render_svg(plot)


def test_encode_raises_on_labels_with_an_unsupported_mark() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var labels: List[String] = ["a", "b"]
    with assert_raises():
        var plot = Plot().mark_line().encode(x=x, y=y, labels=labels).size(400, 300)
        _ = render_svg(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
