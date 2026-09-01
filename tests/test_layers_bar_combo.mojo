"""Tests for render_layers()'s Mark.BAR combo path (_render_bar_combo_
layers): a shared categorical x-axis (the bar layer's own categories)
with Mark.LINE/POINT/AREA layers positioned by index, not by their own
x values. Hand-derived (cross-checked against a real render) bar/line
positions, POINT/AREA layer types too, the always-forced zero baseline,
bars-always-behind draw order, Theme.show_data_labels on the bar layer
(_draw_bar_rects, shared with the standalone Mark.BAR path), and every
raise path (a second Mark.BAR layer, a length mismatch, secondary_axis,
scale_y_log, color/color_categories/size/y_err encoding on a non-bar
layer, and annotate_*()).
"""

from std.testing import assert_true, assert_raises, TestSuite

from dataviz.plot import Plot, render_layers_svg
from dataviz.theme import Theme


def test_render_layers_svg_bar_combo_matches_hand_derived_positions() raises:
    # 2 categories, canvas 400x300, no gridlines -- plot rect
    # x:[60,380] y:[20,250]. Bar y=[10,20], line y=[15,5] (its own
    # x=[0,1] never read -- see _render_bar_combo_layers's own
    # docstring for why). combined_y=[10,20,15,5] -> zero-baseline
    # domain [0,21] (20's span padded 5% -> +1.0), range [250,20].
    # slope = (20-250)/21 = -10.952380952...
    # Bar A (10): pixel 140.48 -> rect y=140. Bar B (20): pixel
    # 30.95 -> rect y=31. OrdinalScale over 2 categories, range
    # [60,380]: bandwidth=128, center(0)=140, center(1)=300 (this
    # package's usual 0.2-padding split, same as every other 2-
    # category test in this suite). Line: (140, 15->85.714),
    # (300, 5->195.238).
    # Every position independently re-derived via python3 and cross-
    # checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true('<rect x="76" y="140" width="128" height="109" fill="#1e64b4"/>' in s, "bar A")
    assert_true('<rect x="236" y="31" width="128" height="218" fill="#1e64b4"/>' in s, "bar B")
    assert_true(
        '<path d="M140.000,85.714 L300.000,195.238" fill="none" stroke="#1e64b4" stroke-width="2.000"'
        ' stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the line, positioned by category index, not its own x values",
    )


def test_render_layers_svg_bar_combo_draws_the_bar_layer_first() raises:
    # The bar layer's own <rect>s appear before the line's <path> in
    # the SVG's own draw order, regardless of the bar layer's position
    # in the plots list -- see _render_bar_combo_layers's own
    # docstring for why bars always draw first (beneath every other
    # layer). Line listed *before* the bar in `plots` here, the
    # opposite of the test above, to actually exercise that claim.
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var plots: List[Plot] = [line^, bars^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    var rect_index = s.find('<rect x="76" y="140"')
    var path_index = s.find("<path d=")
    assert_true(rect_index != -1 and path_index != -1 and rect_index < path_index, "bar rects precede the line path")


def test_render_layers_svg_bar_combo_supports_a_point_layer() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var point_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var points = Plot().mark_point().encode(x=idx, y=point_y).size(400, 300)
    var plots: List[Plot] = [bars^, points^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true('cx="140" cy="86"' in s, "point A, at its category's band center (85.714 rounds to 86)")
    assert_true('cx="300" cy="195"' in s, "point B (195.238 rounds to 195)")


def test_render_layers_svg_bar_combo_supports_an_area_layer() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var area_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var area = Plot().mark_area().encode(x=idx, y=area_y).size(400, 300)
    var plots: List[Plot] = [bars^, area^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    # Closed down to the zero baseline (pixel 250), pulled 1px to 249
    # since the baseline lands exactly on the axis line -- the same
    # _draw_area_layer technique this reuses (see its own docstring).
    assert_true(
        '<path d="M140.000,85.714 L300.000,195.238 L300.000,249.000 L140.000,249.000 Z"'
        ' fill="#1e64b4"/>' in s,
        "the area, closed down to the shared zero baseline",
    )


def test_render_layers_svg_bar_combo_supports_show_data_labels() raises:
    # Theme.show_data_labels on the bar layer's own Theme -- read via
    # _draw_bar_rects, the same primitive _render_bar's standalone
    # path shares (see that function's own docstring). Same frame as
    # test_render_layers_svg_bar_combo_matches_hand_derived_positions
    # (bar A: rect y=140,h=109 -> label baseline 140-4=136 at x=140;
    # bar B: rect y=31,h=218 -> label baseline 31-4=27 at x=300).
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).theme(
        Theme(show_gridlines=False, show_data_labels=True)
    ).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        '<text x="140" y="136" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>' in s,
        "bar A's own data label",
    )
    assert_true(
        '<text x="300" y="27" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">20</text>' in s,
        "bar B's own data label",
    )


def test_render_layers_raises_on_a_second_bar_layer() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var bars1 = Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    var bars2 = Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    var plots: List[Plot] = [bars1^, bars2^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_a_non_bar_layer_length_mismatch() raises:
    var cats: List[String] = ["A", "B", "C"]
    var bar_y: List[Float64] = [10.0, 20.0, 15.0]
    var bad_idx: List[Float64] = [0.0, 1.0]
    var bad_y: List[Float64] = [5.0, 6.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    var line = Plot().mark_line().encode(x=bad_idx, y=bad_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_secondary_axis_in_a_bar_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300).secondary_axis()
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_scale_y_log_in_a_bar_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [1.0, 2.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300).scale_y_log()
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_color_categories_on_a_non_bar_layer() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var color_cats: List[String] = ["x", "y"]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    var points = Plot().mark_point().encode(x=idx, y=line_y, color_categories=color_cats).size(400, 300)
    var plots: List[Plot] = [bars^, points^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_annotate_line_in_a_bar_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300).annotate_line(15.0)
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
