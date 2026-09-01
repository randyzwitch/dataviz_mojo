"""Tests for `Plot.mark_bar(horizontal=True)`/`bar(..., horizontal=True)`
(#121): `_render_horizontal_bar`'s rectangles, negative values
extending left of the baseline instead of below it, the 1px pull-off
when the baseline lands exactly on the frame's left axis line,
`Theme.color_by_sign`/`show_data_labels` support (mirroring the
vertical `Mark.BAR` path's own), the quickplot `bar()` function
matching the fluent `Plot.mark_bar(horizontal=True)` builder exactly,
and the one raise path: a horizontal bar layer inside `render_layers()`.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from dataviz.plot import Plot, render_layers_svg, render_svg
from dataviz.theme import Theme
from dataviz import bar


def test_render_svg_horizontal_bar_matches_hand_derived_rectangles() raises:
    # 2 categories, values=[10, -5], canvas 640x420 default margins
    # (plot area x:[60,620] y:[20,370]). _zero_baseline_y_extent pads
    # only the non-zero-crossing end of [-5,10] (span 15, 5% pad
    # 0.75) to [-5.75, 10.75] -- baseline (0) pixel:
    # 60 + (0-(-5.75))/16.5*560 = 255.15 -> 255 (matches the "0" tick
    # this same render confirms independently). Bar A (10):
    # 60 + (10-(-5.75))/16.5*560 = 594.55 -> 595, rect x=min(255,595)=
    # 255, width=340. Bar B (-5): 60 + (-5-(-5.75))/16.5*560 = 85.45 ->
    # 85, rect x=min(255,85)=85, width=170. Neither edge lands on
    # px0=60, so no 1px pull-off applies here (see the sibling test
    # below for that case). Every position independently re-derived
    # via python3 and cross-checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var plot = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="255" y="38" width="340" height="140" fill="#1e64b4"/>' in s, "bar A, extending right")
    assert_true('<rect x="85" y="213" width="170" height="140" fill="#1e64b4"/>' in s, "bar B, extending left")
    assert_true('<text x="255" y="391"' in s and ">0</text>" in s, "the 0 tick lands where the baseline math predicts")


def test_render_horizontal_bar_pulls_off_axis_line_when_baseline_touches_left_edge() raises:
    # All-positive data -- the domain's low end stays exactly 0
    # (unpadded), so the baseline lands exactly on the frame's own
    # left axis line (px0=60) -- _pull_off_axis_line should nudge
    # every bar's left edge to 61, the same hairline-of-background
    # protection the vertical Mark.BAR path already gets at its own
    # bottom edge.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False)
    )
    var s = render_svg(plot).to_string()
    assert_true('<rect x="61" y="38" width="266" height="140" fill="#1e64b4"/>' in s, "bar A pulled off the axis line")
    assert_true('<rect x="61" y="213" width="532" height="140" fill="#1e64b4"/>' in s, "bar B pulled off the axis line")


def test_render_horizontal_bar_color_by_sign() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var plot = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=vals).theme(t)
    var s = render_svg(plot).to_string()
    assert_true(
        '<rect x="255" y="38" width="340" height="140" fill="#1e64b4"/>' in s,
        "positive bar keeps mark_color even with color_by_sign on",
    )
    assert_true(
        '<rect x="85" y="213" width="170" height="140" fill="#c83c3c"/>' in s,
        "negative bar uses mark_color_negative",
    )


def test_render_svg_horizontal_bar_supports_show_data_labels() raises:
    # Same frame as the hand-derived rectangles test above. Bar A
    # (positive, rect x=255,w=340 -> right edge 595): label sits
    # label_gap(4) right of that edge, left-aligned, vertically
    # centered on its own row (y=38,h=140 -> center 108, +Int(12*0.35)=4
    # -> 112). Bar B (negative, rect x=85 -> left edge 85): label sits
    # 4px left of it, right-aligned, row y=213,h=140 -> center 283,
    # +4 -> 287.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var plot = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False, show_data_labels=True)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<text x="599" y="112" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="start">10</text>' in s,
        "bar A's label, right of the bar, left-aligned",
    )
    assert_true(
        '<text x="81" y="287" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="end">-5</text>' in s,
        "bar B's label, left of the bar, right-aligned",
    )


def test_bar_horizontal_matches_plot_mark_bar_horizontal() raises:
    # The quickplot bar(horizontal=True) convenience function must
    # render identically to the fluent builder it wraps -- the same
    # equivalence test_quickplot.mojo's own test_bar_matches_manual_
    # plot establishes for the vertical (default) case.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var t = Theme(show_gridlines=False)
    var from_quickplot = bar(cats, vals, theme=t, horizontal=True)
    var from_builder = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=vals).theme(t)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())


def test_render_horizontal_bar_empty_data_only_fills_background() raises:
    var plot = Plot().mark_bar(horizontal=True).size(50, 40)  # no encode_categorical() call
    var s = render_svg(plot).to_string()
    assert_true("<rect" in s, "still fills the background")
    assert_true("<line" not in s, "no axis lines drawn for zero categories")


def test_render_layers_raises_on_horizontal_bar_in_a_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=bar_y).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
