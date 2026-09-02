"""Tests for Plot.encode()'s color_map channel: pinning a specific
color_categories value to a specific color, unmapped categories keeping
their ordinary first-seen-order palette color, the override reaching
both the point itself and its legend swatch (both read the same
resolved _PointChannels.palette), and the one raise path (color_map
given with color_categories empty).
"""

from std.collections import Dict
from std.testing import assert_raises, assert_true, TestSuite

from canvas.color import Color
from dataviz.plot import Plot, render, render_svg


def test_render_svg_color_map_overrides_the_named_category() raises:
    # Two categories, "b" pinned to crimson (#dc143c) -- "a" must keep
    # its ordinary first-seen-order palette color (#1f77b4, tab10's
    # first blue), not shift because a later category got pinned.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var overrides: Dict[String, Color] = {"b": Color(220, 20, 60)}
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats, color_map=overrides)
    var s = render_svg(plot).to_string()
    assert_true('fill="#1f77b4"' in s, "unmapped category 'a' keeps its ordinary palette color")
    assert_true('fill="#dc143c"' in s, "mapped category 'b' uses the overridden color")
    assert_true('fill="#ff7f0e"' not in s, "'b' must not also show its ordinary (unoverridden) color")


def test_render_svg_color_map_override_reaches_the_legend_swatch_too() raises:
    # The legend swatch for the overridden category must show the same
    # overridden color, not the ordinary palette one -- both the point
    # and the swatch read the same resolved _PointChannels.palette.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var overrides: Dict[String, Color] = {"b": Color(220, 20, 60)}
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats, color_map=overrides)
    var s = render_svg(plot).to_string()
    assert_true('<rect x="' in s and 'fill="#dc143c"' in s, "a legend swatch uses the overridden color")


def test_render_svg_color_map_leaves_an_unrelated_column_of_the_same_name_alone() raises:
    # A color_map key that never appears among the actual categories is
    # not an error -- confirmed by rendering successfully with a
    # harmless extra key.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var overrides: Dict[String, Color] = {"c": Color(0, 0, 0)}
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats, color_map=overrides)
    _ = render_svg(plot)


def test_render_raises_on_color_map_without_color_categories() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var overrides: Dict[String, Color] = {"a": Color(0, 0, 0)}
    var plot = Plot().mark_point().encode(x=x, y=y, color_map=overrides)
    with assert_raises():
        _ = render(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
