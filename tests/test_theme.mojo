"""Tests for Theme.scale: uniform layout scaling and its purely-additive
default -- split out of what used to be one big test_plot.mojo.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import (
    Plot,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    _build_line_path,
    _index_of,
    _unique_categories,
)
from dataviz_mojo.theme import Theme
from dataviz_mojo import scatter

from _test_helpers import _count_color, _assert_color


def test_render_theme_scale_uniformly_scales_the_whole_layout() raises:
    # Theme.scale=2.0, paired with a canvas twice the width/height, is
    # meant to reproduce the exact same chart at twice the pixel
    # density -- so this reuses (not re-derives) test_render_point_
    # mark_centers_on_the_hand_derived_pixel's own single-(5.0, 5.0)-
    # point setup, at 2x: canvas 800x600 (2x of 400x300), default
    # margins doubled by _Scaled (left=120, right=40, top=40,
    # bottom=100), giving a plot area of x:[120,760], y:[40,500] --
    # exactly 2x test_render_point_mark_centers_on_the_hand_derived_
    # pixel's own x:[60,380], y:[20,250]. The point's own pixel
    # (440, 270) is exactly double (220, 135) for the same reason:
    # LinearScale.to_pixel() of a domain's own midpoint always lands
    # on the range's own midpoint, and doubling a range's endpoints
    # doubles its midpoint too (confirmed directly via the formula,
    # not assumed to "just carry over" from the 1x case).
    var xy: List[Float64] = [5.0]
    var t = Theme(scale=2.0)
    var c = scatter(xy, xy, theme=t, width=800, height=600)

    _assert_color(c, 440, 270, t.mark_color, "scale=2.0's point, exactly 2x the scale=1.0 pixel")
    # The y-axis line itself, confirming the *margin* scaled (not just
    # incidentally landing on the right point pixel) -- plot_x0=120
    # spans the axis line from plot_y0=40 to plot_y1=500, and 270 is
    # well inside that span.
    _assert_color(c, 120, 270, t.axis_color, "scale=2.0's y-axis line, at the doubled margin")


def test_render_theme_scale_default_matches_unscaled_output_exactly() raises:
    # scale's own default (1.0) must reproduce the exact pre-existing
    # unscaled render byte-for-byte -- not just "close", since every
    # pre-existing hand-derived pixel test in this file already
    # depends on that. Cross-checked directly here too: the identical
    # single-point setup, compared pixel-for-pixel between an explicit
    # Theme(scale=1.0) and Theme's own bare default.
    var xy: List[Float64] = [5.0]
    var c_default = scatter(xy, xy, width=400, height=300)
    var c_explicit = scatter(xy, xy, theme=Theme(scale=1.0), width=400, height=300)

    for y in range(c_default.height):
        for x in range(c_default.width):
            var p_default = c_default.get_pixel(x, y)
            var p_explicit = c_explicit.get_pixel(x, y)
            assert_equal(p_default.r, p_explicit.r)
            assert_equal(p_default.g, p_explicit.g)
            assert_equal(p_default.b, p_explicit.b)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
