"""Tests for Theme.show_data_labels on Mark.BAR/GROUPED_BAR/STACKED_BAR:
each bar/sub-bar/segment's own value drawn as text -- hand-derived
(cross-checked against a real render) label placement and formatting
for all three marks, the above-positive/below-negative placement for
BAR/GROUPED_BAR, centered-inside placement for STACKED_BAR, real-value
(not axis-tick-rounded) decimal formatting, and the default-off case.
"""

from std.testing import assert_equal, assert_true, TestSuite

from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme


def test_render_svg_bar_data_labels_match_hand_derived_positions() raises:
    # 2 categories, y=[10.0, -5.5] -- canvas 400x300, no gridlines,
    # plot rect x:[60,380] y:[20,250] (this package's usual default-
    # margin frame for this size). band_start(A)=76, band_start(B)=236,
    # bandwidth=128 (OrdinalScale's usual 0.2-padding split for 2
    # categories over range [60,380]).
    #
    # A (10.0, positive): rect y=30, height=135 -> top edge at 30.
    #   label baseline = 30 - label_gap(4) = 26, centered at
    #   bar_x + bar_width//2 = 76+64 = 140.
    # B (-5.5, negative): rect y=165, height=75 -> bottom edge at 240.
    #   label baseline = 240 + label_gap(4) + font_size(12) = 256,
    #   centered at 236+64 = 300. "-5.5" keeps its real decimal --
    #   _label_decimals(-5.5) is 1, independent of whatever the
    #   y-axis's own tick labels (-5/0/5/10, all integers) use.
    # Every position independently re-derived via python3 and cross-
    # checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.5]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False, show_data_labels=True)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="140" y="26" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>' in s,
        "A's label, above the positive bar",
    )
    assert_true(
        '<text x="300" y="256" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>' in s,
        "B's label, below the negative bar, real decimal kept",
    )


def test_render_svg_bar_draws_no_labels_by_default() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.5]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('text-anchor="middle">10</text>' not in s, "no value label without show_data_labels=True")


def test_render_svg_grouped_bar_data_labels_match_hand_derived_positions() raises:
    # Same 2-category frame as the BAR test above; 2 series (North/
    # South) split each 128px band into two 64px sub-bars.
    # A: North=10 -> rect x=76,y=30,h=135, label at (76+32=108, 26).
    #    South=4 -> rect x=140,y=111,h=54, label at (140+32=172, 107).
    # B: North=-5.5 -> rect x=236,y=165,h=75, label at (236+32=268, 256).
    #    South=8 -> rect x=300,y=57,h=108, label at (300+32=332, 53).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, -5.5], [4.0, 8.0]]
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(
        categories=cats, series_names=names, values=values
    ).theme(Theme(show_gridlines=False, show_data_labels=True, show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<text x="108" y="26" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>' in s, "A/North's label")
    assert_true('<text x="172" y="107" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">4</text>' in s, "A/South's label")
    assert_true('<text x="268" y="256" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>' in s, "B/North's label, below its negative sub-bar")
    assert_true('<text x="332" y="53" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">8</text>' in s, "B/South's label")


def test_render_svg_stacked_bar_data_labels_match_hand_derived_positions() raises:
    # Same 2-category frame, same North/South data -- each segment's
    # label centers *inside* its own rect (vertically centered via
    # this package's usual font_size*0.35 baseline-centering offset,
    # e.g. treemap.mojo/sankey.mojo's own leaf/node labels), not
    # above/below the way BAR/GROUPED_BAR's labels sit.
    # A: North=10 (bottom segment) -> rect y=73,h=108 -> center
    #    73+54=127, +Int(12*0.35)=4 -> 131, at x=76+64=140.
    #    South=4 (stacked on top) -> rect y=30,h=43 -> center 30+21=51,
    #    +4 -> 55, at x=140.
    # B: North=-5.5 (negative, its own independent running total) ->
    #    rect y=181,h=59 -> center 181+29=210, +4 -> 214, at x=236+64=300.
    #    South=8 (positive, unrelated to North's negative stack) ->
    #    rect y=95,h=86 -> center 95+43=138, +4 -> 142, at x=300.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, -5.5], [4.0, 8.0]]
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(
        categories=cats, series_names=names, values=values
    ).theme(Theme(show_gridlines=False, show_data_labels=True, show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<text x="140" y="131" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>' in s, "A/North's label, centered inside its segment")
    assert_true('<text x="140" y="55" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">4</text>' in s, "A/South's label, centered inside its segment")
    assert_true('<text x="300" y="214" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>' in s, "B/North's label, its own segment value, not a cumulative total")
    assert_true('<text x="300" y="142" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">8</text>' in s, "B/South's label")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
