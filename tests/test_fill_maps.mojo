"""`Chart.fill_colors()` and `Chart.fill_patterns()` (#848): pin a
filled mark's category or series to a color or a `HatchStyle` by name,
so it keeps its look when the category list changes.

Checked on the resolved lists every renderer and its legend index, and
on rendered output: a pinned color appears in the SVG, the palette
color it replaced does not, and a pinned pattern is drawn with
`Theme.fill_pattern_by_category` off.
"""

from std.collections import Dict
from std.testing import TestSuite, assert_equal, assert_true

from canvas.color import Color
from dataviz import HatchStyle, render_facets_svg, render_svg, stacked_bar
from dataviz.chart import AnyChart
from dataviz.core.chart_settings import _ChartSettings
from dataviz.core.color_scale import categorical_palette_for
from dataviz.core.fill_maps import _fill_hatches, _fill_palette
from dataviz.plot import Plot


def _red() -> Color:
    return Color(200, 30, 40)


def _count(s: String, needle: String) -> Int:
    var n = 0
    var at = 0
    while True:
        var i = s.find(needle, at)
        if i < 0:
            return n
        n += 1
        at = i + needle.byte_length()


def test_a_pinned_name_keeps_its_color_when_the_order_changes() raises:
    var settings = _ChartSettings()
    settings.fill_colors["b"] = _red()
    var forward: List[String] = ["a", "b", "c"]
    var backward: List[String] = ["c", "b", "a", "d"]
    var f = _fill_palette(settings, forward)
    var b = _fill_palette(settings, backward)
    assert_true(f[1] == _red())
    assert_true(b[1] == _red())
    # Unpinned names keep the palette color for their position.
    var base = categorical_palette_for(settings.theme)
    assert_true(f[0] == base[0])
    assert_true(b[3] == base[3])


def test_patterns_resolve_by_name_with_the_flag_off_and_on() raises:
    var settings = _ChartSettings()
    settings.fill_patterns["b"] = HatchStyle.DOTS
    var names: List[String] = ["a", "b", "c"]
    var off = _fill_hatches(settings, names)
    assert_true(off[0] == HatchStyle.NONE)
    assert_true(off[1] == HatchStyle.DOTS)
    assert_true(off[2] == HatchStyle.NONE)
    settings.theme.fill_pattern_by_category = True
    settings.fill_patterns["c"] = HatchStyle.NONE
    var on = _fill_hatches(settings, names)
    assert_true(on[0] == HatchStyle.NONE)
    assert_true(on[1] == HatchStyle.DOTS)
    # An explicit NONE wins over the cycle.
    assert_true(on[2] == HatchStyle.NONE)


def test_a_pinned_color_replaces_the_palette_color_in_the_svg() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var base = categorical_palette_for(Plot().settings.theme)
    var plain = render_svg(
        Plot().mark_arc().encode_categorical(cats, vals)
    ).to_string()
    var colors = Dict[String, Color]()
    colors["b"] = _red()
    var pinned = render_svg(
        Plot().mark_arc().encode_categorical(cats, vals).fill_colors(colors)
    ).to_string()
    var red = _red().to_hex()
    var replaced = base[1].to_hex()
    assert_equal(_count(plain, red), 0)
    # The slice and its legend swatch.
    assert_true(_count(pinned, red) >= 2)
    assert_equal(_count(pinned, replaced), 0)
    assert_equal(
        _count(pinned, base[0].to_hex()), _count(plain, base[0].to_hex())
    )


def test_a_pinned_pattern_draws_with_the_flag_off() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [1.0, 2.0, 3.0]
    var patterns = Dict[String, HatchStyle]()
    patterns["b"] = HatchStyle.HORIZONTAL
    var plain = render_svg(
        Plot().mark_funnel().encode_categorical(cats, vals)
    ).to_string()
    var pinned = render_svg(
        Plot()
        .mark_funnel()
        .encode_categorical(cats, vals)
        .fill_patterns(patterns)
    ).to_string()
    assert_true(_count(pinned, "<line") > _count(plain, "<line"))


def test_series_marks_resolve_by_series_name() raises:
    var cats: List[String] = ["q1", "q2"]
    var series: List[String] = ["north", "south"]
    var values: List[List[Float64]] = [[1.0, 2.0], [3.0, 4.0]]
    var colors = Dict[String, Color]()
    colors["south"] = _red()
    var svg = render_svg(
        stacked_bar(cats, series, values).fill_colors(colors)
    ).to_string()
    # Two segments and one legend swatch.
    assert_true(_count(svg, _red().to_hex()) >= 3)


def test_one_map_covers_every_panel_of_a_figure() raises:
    var colors = Dict[String, Color]()
    colors["b"] = _red()
    colors["only_elsewhere"] = Color(0, 0, 0)
    var left_cats: List[String] = ["a", "b"]
    var right_cats: List[String] = ["b", "c"]
    var vals: List[Float64] = [1.0, 2.0]
    var plots: List[AnyChart] = [
        AnyChart(
            Plot()
            .mark_arc()
            .encode_categorical(left_cats, vals)
            .fill_colors(colors)
        ),
        AnyChart(
            Plot()
            .mark_arc()
            .encode_categorical(right_cats, vals)
            .fill_colors(colors)
        ),
    ]
    var svg = render_facets_svg(plots, cols=2).to_string()
    # "b" is red in both panels, slice and swatch each, and the name
    # neither panel has is ignored rather than refused.
    assert_true(_count(svg, _red().to_hex()) >= 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
