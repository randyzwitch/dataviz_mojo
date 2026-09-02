"""Tests for `PointShape`/`Theme.shape_by_category`: the fixed shape
cycle itself, exact per-shape render geometry (SVG), legend swatch
integration, and the "no-op without `color_categories`" precedent
`Theme.color_by_sign` already sets for a comparable mismatch.
"""

from std.testing import assert_equal, assert_true, TestSuite

from dataviz import PointShape, default_marker_shapes
from dataviz.plot import Plot, render_svg
from dataviz.theme import Theme


def test_default_marker_shapes_returns_six_shapes_starting_with_circle() raises:
    # CIRCLE first so default_marker_shapes()[0] reproduces fill_
    # circle_aa's own pre-existing look for a chart's first category --
    # see PointShape's own module docstring (marker.mojo).
    var shapes = default_marker_shapes()
    assert_equal(len(shapes), 6)
    assert_true(shapes[0] == PointShape.CIRCLE, "index 0 is CIRCLE")
    assert_true(shapes[1] == PointShape.SQUARE, "index 1 is SQUARE")
    assert_true(shapes[2] == PointShape.TRIANGLE, "index 2 is TRIANGLE")
    assert_true(shapes[3] == PointShape.DIAMOND, "index 3 is DIAMOND")
    assert_true(shapes[4] == PointShape.CROSS, "index 4 is CROSS")
    assert_true(shapes[5] == PointShape.X, "index 5 is X")


def test_point_shape_eq_distinguishes_every_shape() raises:
    # Reflexive, and no two distinct shapes ever compare equal -- a
    # plain O(n^2) pairwise check over all 6, the cheapest way to state
    # "all distinct" without hand-picking which pairs to check.
    var shapes = default_marker_shapes()
    for i in range(len(shapes)):
        assert_true(shapes[i] == shapes[i], "reflexive")
        for j in range(len(shapes)):
            if i != j:
                assert_true(not (shapes[i] == shapes[j]), "distinct shapes never compare equal")


def test_render_svg_shape_by_category_matches_hand_derived_geometry() raises:
    # 6 categories -> all 6 PointShapes, one per point, cycling
    # default_marker_shapes() in first-seen category order (see
    # _categorical_indices' docstring). show_legend=False keeps this
    # test about the *point* geometry only -- the legend's own shape
    # icons are covered separately below, on a plot whose column
    # reservation this test doesn't want to also re-derive.
    #
    # x = [0,2,4,6,8,10] over the padded domain [-0.5,10.5] (5% pad on
    # [0,10]'s span, the same _data_extent rule every continuous-x test
    # here already uses), canvas 400x300, no legend so the plot area is
    # the full x:[60,380] (default margins) -- pixel columns
    # [75,133,191,249,307,365], solved from LinearScale's slope/
    # intercept formula, cross-checked in Python, not read off the
    # code's output. y is constant 0.0 -> zero-span domain padded to
    # [-1,1], landing every point at the same pixel row, y=135. Default
    # point_radius=3.5 rounds (round-half-away-from-zero) to a 4px
    # radius, same as every other point test here.
    var x: List[Float64] = [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    var cats: List[String] = ["A", "B", "C", "D", "E", "F"]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cats)
        .theme(Theme(shape_by_category=True, show_legend=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()

    # A -> CIRCLE, palette[0] #1f77b4 -- unchanged fill_circle_aa look.
    assert_true('<circle cx="75" cy="135" r="4" fill="#1f77b4"/>' in s, "A -> CIRCLE")
    # B -> SQUARE, palette[1] #ff7f0e -- an 8x8 rect (2*radius per
    # side) centered on (133,135).
    assert_true('<rect x="129" y="131" width="8" height="8" fill="#ff7f0e"/>' in s, "B -> SQUARE")
    # C -> TRIANGLE, palette[2] #2ca02c -- equilateral, top vertex
    # straight up (cy-r), the other two at +-30deg either side of
    # straight down (cy+r*0.5, cx+-r*cos(30deg), cos(30deg)=0.8660254).
    assert_true(
        '<path d="M191.000,131.000 L194.464,137.000 L187.536,137.000 Z" fill="#2ca02c"/>' in s,
        "C -> TRIANGLE",
    )
    # D -> DIAMOND, palette[3] #d62728 -- a rotated square, one vertex
    # per cardinal direction, each exactly radius from center.
    assert_true(
        '<path d="M249.000,131.000 L253.000,135.000 L249.000,139.000 L245.000,135.000 Z"'
        ' fill="#d62728"/>' in s,
        "D -> DIAMOND",
    )
    # E -> CROSS, palette[4] #9467bd -- two perpendicular strokes,
    # stroke-width = radius*0.65 = 2.6.
    assert_true(
        '<line x1="307" y1="131" x2="307" y2="139" stroke="#9467bd" stroke-width="2.600"'
        ' stroke-linecap="round"/>' in s,
        "E -> CROSS (vertical stroke)",
    )
    assert_true(
        '<line x1="303" y1="135" x2="311" y2="135" stroke="#9467bd" stroke-width="2.600"'
        ' stroke-linecap="round"/>' in s,
        "E -> CROSS (horizontal stroke)",
    )
    # F -> X, palette[5] #8c564b -- CROSS's own two strokes, rotated
    # 45deg (diag = round(radius*cos(45deg)) = round(2.828...) = 3,
    # round-half-away-from-zero, same as every other pixel rounding
    # here).
    assert_true(
        '<line x1="362" y1="132" x2="368" y2="138" stroke="#8c564b" stroke-width="2.600"'
        ' stroke-linecap="round"/>' in s,
        "F -> X (backslash diagonal)",
    )
    assert_true(
        '<line x1="362" y1="138" x2="368" y2="132" stroke="#8c564b" stroke-width="2.600"'
        ' stroke-linecap="round"/>' in s,
        "F -> X (forward-slash diagonal)",
    )


def test_render_svg_shape_by_category_legend_matches_hand_derived_icons() raises:
    # The exact same 2-category setup test_point.mojo's own test_
    # render_categorical_color_matches_hand_derived_palette_entries
    # already hand-derives (x=[0,10], y=[0,0], cats=["A","B"], canvas
    # 400x300 -- plot area narrows to x:[60,250] for the 130px legend
    # column, points land at pixel x=69/241, y=135) -- confirming shape_
    # by_category changes the *drawn shape*, not that already-verified
    # layout math, plus covering what that test doesn't: the legend's
    # own per-row icon.
    #
    # Legend column starts at legend_x = frame.px1 + margin_right =
    # 250+20 = 270, legend_y = frame.py0 = 20 (default margin_top on a
    # 300-tall canvas) -- see _render_generic's own _draw_point_layer
    # call (plot.mojo). Row height = legend_swatch_size + legend_row_
    # gap = 14+8 = 22 (both Theme defaults). Icon radius = legend_
    # swatch_size // 2 = 7, centered in each row's own swatch cell.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cats)
        .theme(Theme(shape_by_category=True))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()

    # Points: A -> CIRCLE (unchanged), B -> SQUARE.
    assert_true('<circle cx="69" cy="135" r="4" fill="#1f77b4"/>' in s, "point A -> CIRCLE")
    assert_true('<rect x="237" y="131" width="8" height="8" fill="#ff7f0e"/>' in s, "point B -> SQUARE")
    # Legend row 0 (A): center (270+7, 20+7) = (277, 27).
    assert_true('<circle cx="277" cy="27" r="7" fill="#1f77b4"/>' in s, "legend A -> CIRCLE icon")
    # Legend row 1 (B): row_y = 20+22 = 42, center (277, 49).
    assert_true('<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "legend B -> SQUARE icon")


def test_render_svg_categorical_color_legend_stays_a_flat_swatch_by_default() raises:
    # shape_by_category defaults False -- the exact pre-existing
    # test_point.mojo precedent's own legend swatch (a flat square at
    # the swatch's own top-left corner, not shape-centered) must stay
    # byte-identical, regardless of marker.mojo's own existence.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "legend A stays a flat swatch")
    assert_true('<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "legend B stays a flat swatch")


def test_shape_by_category_is_a_noop_without_color_categories() raises:
    # No category column to index a shape from -- shape_by_category
    # changes nothing, the same "a Theme flag only some marks/
    # encodings read" precedent color_by_sign already sets (see
    # Theme.shape_by_category's own docstring). Same single-(5.0,5.0)-
    # point setup test_point.mojo's own test_render_svg_point_mark_
    # matches_hand_derived_coordinates already hand-derives.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(shape_by_category=True)).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in s, "still a plain circle, unaffected")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
