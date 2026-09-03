"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_sunburst.mojo`: Tests for Mark.SUNBURST: ring-sector geometry per depth level,
  encode_hierarchy()'s shared validation (raster + SVG) -- see
  sunburst.mojo's docstrings for the rules verified here.

- `test_tree.mojo`: Tests for Mark.TREE (top-to-bottom node-link diagram): leaf/depth
  positioning, per-branch edge/marker color, encode_hierarchy()'s shared validation (raster + SVG) -- see tree.mojo's docstrings for
  the rules verified here.

- `test_treemap.mojo`: Tests for Mark.TREEMAP (slice-and-dice hierarchy chart): the
  alternating-axis split, boundary-rounding correctness across two
  levels, encode_hierarchy()'s shared validation (raster + SVG) --
  see treemap.mojo's docstrings for the rules verified here.

- `test_chord.mojo`: Tests for Mark.CHORD: node ring sectors plus flow ribbons (raster +
  smoke-level SVG) -- see chord.mojo's docstrings for the angle/
  ribbon-geometry rules verified here.

- `test_arc_diagram.mojo`: Tests for Mark.ARC_DIAGRAM: node line-up positions, semicircular
  edge-arc geometry/width, per-from-node color, encode_chord()'s shared validation (raster + SVG) -- see arc_diagram.mojo's docstrings for the rules verified here.

- `test_graph.mojo`: Tests for Mark.GRAPH: circular node positioning, straight-line edge
  geometry/width, per-from-node color, encode_chord()'s shared
  validation (raster + SVG) -- see graph.mojo's docstrings for the
  rules verified here.

- `test_sankey.mojo`: Tests for Mark.SANKEY: column (longest-path) layout, node/ribbon
  geometry, skip-edge pass-through routing, cycle detection, encode_
  chord()'s shared validation (raster + SVG) -- see sankey.mojo's docstrings for the rules verified here.

"""

from _test_helpers import BG, _assert_color
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.vector.svg import SvgCanvas
from dataviz import arc_diagram, chord, graph, sankey, sunburst, tree, treemap
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_sunburst.mojo
# ---------------------------------------------------------------

def test_render_sunburst_matches_hand_derived_ring_sectors() raises:
    # root -> A (50% of root) -> A1/A2 (50/50 split of A's span);
    # root -> B (50% of root) -> B1 (100% of B's span, B's only
    # child). Canvas 400x300, show_legend=False: plot area x:[60,380],
    # y:[20,250] -> center (220,135), max radius 103.5 (the same no-
    # legend numbers every polar-family mark's tests already
    # derive for this exact canvas size). max_depth=2 -> ring_width
    # 51.75: ring 1 spans [0,51.75], ring 2 spans [51.75,103.5].
    #
    # A spans -90.90 degrees (bisector 0, due east); B spans 90.270
    # (bisector 180, due west). A1 spans -90.0 (bisector -45); A2
    # spans 0.90 (bisector 45); B1 spans A's full 90.270 (same
    # as B itself, bisector 180). Every one of the 5 points below sits
    # at a radius safely inside its ring (2 per branch's ring 2, 1 more
    # each ring 1), away from any boundary.
    var ids: List[String] = ["root", "A", "B", "A1", "A2", "B1"]
    var parents: List[String] = ["", "root", "root", "A", "A", "B"]
    var values: List[Float64] = [0.0, 0.0, 0.0, 1.0, 1.0, 2.0]
    var t = Theme(show_legend=False)
    var _hoisted1 = sunburst(ids, parents, values, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 277, 78, palette[0], "A1, ring 2, bisector -45 degrees")
    _assert_color(c, 277, 192, palette[0], "A2, ring 2, bisector 45 degrees")
    _assert_color(c, 140, 135, palette[1], "B1, ring 2, bisector 180 degrees")
    _assert_color(c, 250, 135, palette[0], "A, ring 1, bisector 0 degrees")
    _assert_color(c, 190, 135, palette[1], "B, ring 1, bisector 180 degrees")


def test_render_sunburst_raises_on_multiple_roots() raises:
    var ids: List[String] = ["a", "b"]
    var parents: List[String] = ["", ""]
    var values: List[Float64] = [1.0, 1.0]
    with assert_raises():
        var _hoisted2 = sunburst(ids, parents, values, width=200, height=150)
        _ = render(_hoisted2)


def test_render_sunburst_raises_on_no_root() raises:
    var ids: List[String] = ["a", "b"]
    var parents: List[String] = ["b", "a"]
    var values: List[Float64] = [1.0, 1.0]
    with assert_raises():
        var _hoisted3 = sunburst(ids, parents, values, width=200, height=150)
        _ = render(_hoisted3)


def test_render_sunburst_raises_on_unresolved_parent_id() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "missing"]
    var values: List[Float64] = [0.0, 1.0]
    with assert_raises():
        var _hoisted4 = sunburst(ids, parents, values, width=200, height=150)
        _ = render(_hoisted4)


def test_render_sunburst_raises_on_duplicate_id() raises:
    var ids: List[String] = ["root", "a", "a"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 1.0, 1.0]
    with assert_raises():
        var _hoisted5 = sunburst(ids, parents, values, width=200, height=150)
        _ = render(_hoisted5)


def test_render_sunburst_raises_on_negative_value() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root"]
    var values: List[Float64] = [0.0, -1.0]
    with assert_raises():
        var _hoisted6 = sunburst(ids, parents, values, width=200, height=150)
        _ = render(_hoisted6)


def test_render_sunburst_raises_on_all_zero_values() raises:
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 0.0, 0.0]
    with assert_raises():
        var _hoisted7 = sunburst(ids, parents, values, width=200, height=150)
        _ = render(_hoisted7)


def test_render_sunburst_raises_on_mismatched_length() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root", "extra"]
    var values: List[Float64] = [0.0, 1.0]
    with assert_raises():
        var _hoisted8 = sunburst(ids, parents, values, width=200, height=150)
        _ = render(_hoisted8)


def test_render_sunburst_empty_data_only_fills_background() raises:
    var ids = List[String]()
    var parents = List[String]()
    var values = List[Float64]()
    var _hoisted9 = sunburst(ids, parents, values, width=100, height=80)
    var c = render(_hoisted9)
    _assert_color(c, 50, 40, BG, "no hierarchy: nothing drawn but the background")


def test_render_sunburst_raises_on_a_cycle() raises:
    # "a" and "b" are each other's parent. Every other check passes --
    # no duplicate ids, both parent_ids resolve, exactly one empty-
    # parent root -- so nothing but a reachability check catches this:
    # without it, the traversal simply never reaches either row, and
    # both would silently vanish from the chart, taking 16 of the 21
    # total value with them.
    var ids: List[String] = ["root", "leaf", "a", "b"]
    var parents: List[String] = ["", "root", "b", "a"]
    var values: List[Float64] = [0.0, 5.0, 7.0, 9.0]
    with assert_raises():
        var _hoisted10 = sunburst(ids, parents, values, width=200, height=150)
        _ = render(_hoisted10)


def test_render_sunburst_raises_on_a_disconnected_component() raises:
    # A self-parented row: "orphan" is its parent, so it resolves
    # and is never reachable. The degenerate one-node case of the same
    # cycle bug above, caught by the same check.
    var ids: List[String] = ["root", "orphan"]
    var parents: List[String] = ["", "orphan"]
    var values: List[Float64] = [0.0, 3.0]
    with assert_raises():
        var _hoisted11 = sunburst(ids, parents, values, width=200, height=150)
        _ = render(_hoisted11)

# ---------------------------------------------------------------
# from tests/test_tree.mojo
# ---------------------------------------------------------------

def test_render_tree_matches_hand_derived_positions() raises:
    # root -> A, B (both leaves, no grandchildren) -- the simplest
    # non-trivial tree: 2 leaves, max_depth 1. Canvas 400x300, show_
    # legend=False: plot area x:[60,380], y:[20,250] (the standard
    # no-legend numbers every mark's tests derive for this
    # exact canvas size). 2 leaves -> A's slot 0 maps to plot_x0
    # (60), B's slot 1 maps to plot_x1 (380); root's slot is
    # the average (0.5), maps to the horizontal center (220). depth 0
    # (root) maps to plot_y0 (20), depth 1 (A, B) to plot_y1 (250)
    # (see this file's SVG test).
    var ids: List[String] = ["root", "A", "B"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 1.0, 1.0]
    var t = Theme(show_legend=False)
    var _hoisted1 = tree(ids, parents, values, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 220, 20, t.text_color, "root's marker -- no branch, stays text_color")
    _assert_color(c, 60, 250, palette[0], "A's marker -- root's first child, palette[0]")
    _assert_color(c, 380, 250, palette[1], "B's marker -- root's second child, palette[1]")
    # A point along the root->A edge, well clear of either marker's
    # radius: the edge from (220,20) to (60,250), at its 25%
    # mark -> (220 - 0.25*160, 20 + 0.25*230) = (180, 77.5). The exact
    # fractional y (77.5) sits right on a pixel-row boundary, which
    # AA-blends at y=78 -- y=77 lands solidly on the stroke instead.
    _assert_color(c, 180, 77, palette[0], "along the root->A edge, 25% of the way down")


def test_render_tree_svg_matches_confirmed_geometry() raises:
    var ids: List[String] = ["root", "A", "B"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 1.0, 1.0]
    var plot = Plot().mark_tree().encode_hierarchy(ids=ids, parent_ids=parents, values=values).theme(
        Theme(show_legend=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<line x1="220" y1="20" x2="60" y2="250" stroke="#1f77b4"' in s, "root->A edge")
    assert_true('<line x1="220" y1="20" x2="380" y2="250" stroke="#ff7f0e"' in s, "root->B edge")
    assert_true('<circle cx="220" cy="20" r="4" fill="#282828"/>' in s, "root's marker")
    assert_true('<circle cx="60" cy="250" r="4" fill="#1f77b4"/>' in s, "A's marker")
    assert_true('<circle cx="380" cy="250" r="4" fill="#ff7f0e"/>' in s, "B's marker")


def test_render_tree_raises_on_multiple_roots() raises:
    var ids: List[String] = ["a", "b"]
    var parents: List[String] = ["", ""]
    var values: List[Float64] = [1.0, 1.0]
    with assert_raises():
        var _hoisted2 = tree(ids, parents, values, width=200, height=150)
        _ = render(_hoisted2)


def test_render_tree_raises_on_negative_value() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root"]
    var values: List[Float64] = [0.0, -1.0]
    with assert_raises():
        var _hoisted3 = tree(ids, parents, values, width=200, height=150)
        _ = render(_hoisted3)


def test_render_tree_raises_on_mismatched_length() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root", "extra"]
    var values: List[Float64] = [0.0, 1.0]
    with assert_raises():
        var _hoisted4 = tree(ids, parents, values, width=200, height=150)
        _ = render(_hoisted4)


def test_render_tree_empty_data_only_fills_background() raises:
    var ids = List[String]()
    var parents = List[String]()
    var values = List[Float64]()
    var _hoisted5 = tree(ids, parents, values, width=100, height=80)
    var c = render(_hoisted5)
    _assert_color(c, 50, 40, BG, "no hierarchy: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_treemap.mojo
# ---------------------------------------------------------------

def test_render_treemap_matches_hand_derived_rects() raises:
    # root -> A (total 30: A1=20, A2=10), root -> B (total 10: B1=10,
    # B's only child). Canvas 400x300, show_legend=False: plot area
    # x:[60,380], y:[20,250] (the standard no-legend numbers every
    # mark's tests derive for this exact canvas size).
    #
    # depth 0 (root's children, A/B) splits along x: A gets
    # 30/40=75% of the 320px width -> 240px, x:[60,300]; B gets the
    # remaining 80px, x:[300,380]. depth 1 (A's children) splits
    # along y instead (alternating axis): A1 gets 20/30=66.7% of the
    # 230px height -> 153px, y:[20,173]; A2 gets the rest, y:[173,250].
    # B1, B's only child, gets 100% of B's rect unchanged (see this
    # file's SVG test).
    var ids: List[String] = ["root", "A", "B", "A1", "A2", "B1"]
    var parents: List[String] = ["", "root", "root", "A", "A", "B"]
    var values: List[Float64] = [0.0, 0.0, 0.0, 20.0, 10.0, 10.0]
    var t = Theme(show_legend=False)
    var _hoisted1 = treemap(ids, parents, values, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 150, 80, palette[0], "A1's rect, well inside its bounds")
    _assert_color(c, 150, 220, palette[0], "A2's rect, well inside its bounds")
    _assert_color(c, 340, 100, palette[1], "B1's rect (all of B's space), well inside its bounds")


def test_render_treemap_svg_matches_confirmed_rects() raises:
    var ids: List[String] = ["root", "A", "B", "A1", "A2", "B1"]
    var parents: List[String] = ["", "root", "root", "A", "A", "B"]
    var values: List[Float64] = [0.0, 0.0, 0.0, 20.0, 10.0, 10.0]
    var plot = Plot().mark_treemap().encode_hierarchy(ids=ids, parent_ids=parents, values=values).theme(
        Theme(show_legend=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="60" y="20" width="240" height="153" fill="#1f77b4"/>' in s, "A1")
    assert_true('<rect x="60" y="173" width="240" height="77" fill="#1f77b4"/>' in s, "A2")
    assert_true('<rect x="300" y="20" width="80" height="230" fill="#ff7f0e"/>' in s, "B1")


def test_render_treemap_raises_on_multiple_roots() raises:
    var ids: List[String] = ["a", "b"]
    var parents: List[String] = ["", ""]
    var values: List[Float64] = [1.0, 1.0]
    with assert_raises():
        var _hoisted2 = treemap(ids, parents, values, width=200, height=150)
        _ = render(_hoisted2)


def test_render_treemap_raises_on_negative_value() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root"]
    var values: List[Float64] = [0.0, -1.0]
    with assert_raises():
        var _hoisted3 = treemap(ids, parents, values, width=200, height=150)
        _ = render(_hoisted3)


def test_render_treemap_raises_on_all_zero_values() raises:
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 0.0, 0.0]
    with assert_raises():
        var _hoisted4 = treemap(ids, parents, values, width=200, height=150)
        _ = render(_hoisted4)


def test_render_treemap_raises_on_mismatched_length() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root", "extra"]
    var values: List[Float64] = [0.0, 1.0]
    with assert_raises():
        var _hoisted5 = treemap(ids, parents, values, width=200, height=150)
        _ = render(_hoisted5)


def test_render_treemap_empty_data_only_fills_background() raises:
    var ids = List[String]()
    var parents = List[String]()
    var values = List[Float64]()
    var _hoisted6 = treemap(ids, parents, values, width=100, height=80)
    var c = render(_hoisted6)
    _assert_color(c, 50, 40, BG, "no hierarchy: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_chord.mojo
# ---------------------------------------------------------------

def test_render_chord_two_nodes_one_edge_matches_hand_derived_geometry() raises:
    # 2 nodes ("A", "B"), one edge A->B, value 10 -- each node's total flow is 10 (its only edge), so the two ring sectors split
    # the circle exactly in half, the same -pi/2->pi/2 (A) / pi/2->3pi/2
    # (B) split test_render_arc_mark_matches_hand_derived_wedge_colors
    # confirms for two equal Mark.ARC wedges (this mark reuses
    # that exact start-at-12-o'clock, sweep-clockwise convention).
    # Canvas 400x300, show_legend=False (sidesteps the legend column's
    # font-metric-dependent width): plot area x:[60,380], y:[20,250]
    # (Theme's default margins, no dynamic-left-margin case here --
    # Mark.CHORD has no y-axis labels at all), center (220,135), radius
    # = min(320,230)/2*0.9 = 103.5, inner_radius = radius*0.92 = 95.22.
    #
    # With only one edge, that edge's sub-arc allocation *is* each
    # node's full span -- so the ribbon's rim segments trace
    # A's entire rim (-pi/2 -> pi/2) then B's entire rim (pi/2 -> 3pi/2
    # == -pi/2), a full 2*pi sweep back to the start point, with both
    # "cross" quad_curve_to calls degenerating to a single point (their
    # start and end angles are identical -- pi/2 and -pi/2 respectively).
    # The whole ribbon path is therefore just the full circle's circumference at inner_radius, traced once -- filling it fills the
    # *entire* inner disk in the ribbon's color (A's palette color,
    # index 0), not just "A's half": the inner-disk sample point on
    # B's geometric side (left of center) is still palette[0], not
    # palette[1].
    var from_cats: List[String] = ["A"]
    var to_cats: List[String] = ["B"]
    var values: List[Float64] = [10.0]
    var t = Theme(show_legend=False)
    var _hoisted1 = chord(from_cats, to_cats, values, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()

    # Ring band (radius in (95.22, 103.5)), right of center -> A.
    _assert_color(c, 319, 135, palette[0], "A's ring sector, right of center")
    # Ring band, left of center -> B.
    _assert_color(c, 121, 135, palette[1], "B's ring sector, left of center")
    # Inner disk (radius < 95.22): entirely the one ribbon's color.
    _assert_color(c, 270, 135, palette[0], "inner disk, right of center -- A's ribbon")
    _assert_color(c, 170, 135, palette[0], "inner disk, left of center (B's geometric side) -- still A's ribbon")
    _assert_color(c, 220, 135, palette[0], "dead center -- still inside the one ribbon's filled disk")
    _assert_color(c, 10, 10, BG, "well outside the whole circle -- background")


def test_render_chord_svg_writes_ribbon_and_ring_paths() raises:
    # A smoke-level structural check (not a pixel-exact one -- a
    # curved, multi-segment filled path isn't practically hand-derived
    # the way a rect-based mark's SVG output is): three nodes, real
    # flows between them, confirms real <path>/<path fill=.> markup
    # comes out for both the ribbons and the ring sectors, not just an
    # empty or background-only canvas.
    var from_cats: List[String] = ["A", "B"]
    var to_cats: List[String] = ["B", "C"]
    var values: List[Float64] = [5.0, 3.0]
    var plot = Plot().mark_chord().encode_chord(
        from_categories=from_cats, to_categories=to_cats, values=values
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true("<path " in s, "at least one ribbon drawn as a real SVG path")
    # default_categorical_palette()'s first three entries, hardcoded
    # the same way test_population_pyramid.mojo's SVG test hardcodes
    # palette hex values (Color(31,119,180)/(255,127,14)/(44,160,44)).
    assert_true("#1f77b4" in s, "node A's ring sector color appears")
    assert_true("#ff7f0e" in s, "node B's ring sector color appears")
    assert_true("#2ca02c" in s, "node C's ring sector color appears")


def test_render_chord_raises_on_mismatched_length() raises:
    var from_cats: List[String] = ["a", "b", "c"]
    var to_cats: List[String] = ["x", "y"]
    var values: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = chord(from_cats, to_cats, values, width=200, height=150)
        _ = render(_hoisted2)


def test_render_chord_raises_on_negative_value() raises:
    var from_cats: List[String] = ["a"]
    var to_cats: List[String] = ["b"]
    var values: List[Float64] = [-1.0]
    with assert_raises():
        var _hoisted3 = chord(from_cats, to_cats, values, width=200, height=150)
        _ = render(_hoisted3)


def test_render_chord_raises_on_all_zero_values() raises:
    var from_cats: List[String] = ["a"]
    var to_cats: List[String] = ["b"]
    var values: List[Float64] = [0.0]
    with assert_raises():
        var _hoisted4 = chord(from_cats, to_cats, values, width=200, height=150)
        _ = render(_hoisted4)


def test_render_chord_empty_data_only_fills_background() raises:
    var from_cats = List[String]()
    var to_cats = List[String]()
    var values = List[Float64]()
    var _hoisted5 = chord(from_cats, to_cats, values, width=200, height=150)
    var c = render(_hoisted5)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")

# ---------------------------------------------------------------
# from tests/test_arc_diagram.mojo
# ---------------------------------------------------------------

def test_render_arc_diagram_matches_hand_derived_arcs() raises:
    # 3 nodes (A, B, C -- first-seen order across from-then-to:
    # "A","B" then "B","C"), edges A->B (value 10, the domain's max) and B->C (value 5, half that). Canvas 400x300, default
    # theme: plot area x:[60,380], y:[20,250] -> 3 evenly spaced nodes
    # at x=60/220/380, all on the shared baseline y=250 (the bottom of
    # the inner plot rect).
    #
    # Edge A->B: center (140,250), radius 80 -- its peak (the
    # semicircle's top point, straight up from center) is (140,
    # 170). Edge B->C: center (300,250), radius 80, peak (300,170).
    # Edge width: A->B at frac 10/10=1.0 -> line_width + line_width*2
    # = 6; B->C at frac 5/10=0.5 -> line_width + line_width = 4 (not
    # directly asserted here, confirmed in this file's SVG test
    # instead, where the exact stroke-width is visible in the path
    # markup).
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B", "C"]
    var v: List[Float64] = [10.0, 5.0]
    var _hoisted1 = arc_diagram(from_c, to_c, v, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 140, 170, palette[0], "A->B's arc, at its peak")
    _assert_color(c, 300, 170, palette[1], "B->C's arc, at its peak")
    _assert_color(c, 60, 250, palette[0], "node A's marker")
    _assert_color(c, 220, 250, palette[1], "node B's marker")
    _assert_color(c, 380, 250, palette[2], "node C's marker")


def test_render_arc_diagram_svg_matches_confirmed_geometry() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B", "C"]
    var v: List[Float64] = [10.0, 5.0]
    var plot = Plot().mark_arc_diagram().encode_chord(from_categories=from_c, to_categories=to_c, values=v).theme(
        Theme()
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M60.000,250.000 A80.000,80.000 0 1,1 220.000,250.000" fill="none" stroke="#1f77b4"'
        ' stroke-width="6.000"' in s,
        "A->B's arc: center (140,250), radius 80, width 6 (frac 1.0)",
    )
    assert_true(
        '<path d="M220.000,250.000 A80.000,80.000 0 1,1 380.000,250.000" fill="none" stroke="#ff7f0e"'
        ' stroke-width="4.000"' in s,
        "B->C's arc: center (300,250), radius 80, width 4 (frac 0.5)",
    )


def test_render_arc_diagram_self_loop_draws_nothing_but_doesnt_raise() raises:
    var from_c: List[String] = ["A", "A"]
    var to_c: List[String] = ["A", "B"]
    var v: List[Float64] = [5.0, 5.0]
    # No assertion failure/raise means the self-loop (A->A) was safely
    # skipped rather than crashing on a zero-diameter arc.
    var _hoisted2 = arc_diagram(from_c, to_c, v, width=200, height=150)
    var c = render(_hoisted2)
    _ = c


def test_render_arc_diagram_raises_on_negative_value() raises:
    var from_c: List[String] = ["A"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [-1.0]
    with assert_raises():
        var _hoisted3 = arc_diagram(from_c, to_c, v, width=200, height=150)
        _ = render(_hoisted3)


def test_render_arc_diagram_raises_on_mismatched_length() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted4 = arc_diagram(from_c, to_c, v, width=200, height=150)
        _ = render(_hoisted4)


def test_render_arc_diagram_empty_data_only_fills_background() raises:
    var from_c = List[String]()
    var to_c = List[String]()
    var v = List[Float64]()
    var _hoisted5 = arc_diagram(from_c, to_c, v, width=100, height=80)
    var c = render(_hoisted5)
    _assert_color(c, 50, 40, BG, "no edges: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_graph.mojo
# ---------------------------------------------------------------

def test_render_graph_matches_hand_derived_edges() raises:
    # 3 nodes (A, B, C -- first-seen order across from-then-to),
    # edges A->B (value 10, the domain's max) and B->C (value 5,
    # half that). Canvas 400x300, default theme: plot area x:[60,380],
    # y:[20,250] -> center (220,135), max radius 103.5 (the same
    # no-legend-needed numbers every polar-family mark's tests already
    # derive for this exact canvas size -- Mark.GRAPH never reserves
    # legend space at all).
    #
    # 3 nodes evenly spaced starting at 12 o'clock, sweeping clockwise
    # (Mark.ARC's convention, reused for position only): A at -90
    # degrees -> (220,32); B at 30 degrees -> (310,187); C at 150
    # degrees -> (130,187) (see this file's SVG test). Edge
    # midpoints (well clear of either endpoint's marker) confirm
    # each edge's color follows its "from" node.
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B", "C"]
    var v: List[Float64] = [10.0, 5.0]
    var _hoisted1 = graph(from_c, to_c, v, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 265, 110, palette[0], "A->B's edge, at its midpoint")
    _assert_color(c, 220, 187, palette[1], "B->C's edge, at its midpoint")
    _assert_color(c, 220, 32, palette[0], "node A's marker")
    _assert_color(c, 310, 187, palette[1], "node B's marker")
    _assert_color(c, 130, 187, palette[2], "node C's marker")


def test_render_graph_svg_matches_confirmed_geometry() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B", "C"]
    var v: List[Float64] = [10.0, 5.0]
    var plot = Plot().mark_graph().encode_chord(from_categories=from_c, to_categories=to_c, values=v).theme(Theme()).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="220" y1="32" x2="310" y2="187" stroke="#1f77b4" stroke-width="6.000"' in s,
        "A->B: node A (220,32) to node B (310,187), width 6 (frac 1.0)",
    )
    assert_true(
        '<line x1="310" y1="187" x2="130" y2="187" stroke="#ff7f0e" stroke-width="4.000"' in s,
        "B->C: node B (310,187) to node C (130,187), width 4 (frac 0.5)",
    )


def test_render_graph_self_loop_draws_nothing_but_doesnt_raise() raises:
    var from_c: List[String] = ["A", "A"]
    var to_c: List[String] = ["A", "B"]
    var v: List[Float64] = [5.0, 5.0]
    var _hoisted2 = graph(from_c, to_c, v, width=200, height=150)
    var c = render(_hoisted2)
    _ = c


def test_render_graph_raises_on_negative_value() raises:
    var from_c: List[String] = ["A"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [-1.0]
    with assert_raises():
        var _hoisted3 = graph(from_c, to_c, v, width=200, height=150)
        _ = render(_hoisted3)


def test_render_graph_raises_on_mismatched_length() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted4 = graph(from_c, to_c, v, width=200, height=150)
        _ = render(_hoisted4)


def test_render_graph_empty_data_only_fills_background() raises:
    var from_c = List[String]()
    var to_c = List[String]()
    var v = List[Float64]()
    var _hoisted5 = graph(from_c, to_c, v, width=100, height=80)
    var c = render(_hoisted5)
    _assert_color(c, 50, 40, BG, "no edges: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_sankey.mojo
# ---------------------------------------------------------------

def test_render_sankey_matches_hand_derived_nodes_and_ribbon() raises:
    # 2 nodes (A, B), one edge A->B (value 10 -- both node's entire inflow/outflow, so no imbalance gap). Canvas 400x300,
    # default theme: plot area x:[60,380], y:[20,250]. 2 columns
    # (A at column 0, B at column 1): node width 12, column x
    # positions 60 (column 0) and 368 (column 1, pulled in by one
    # node-width so the last column's node doesn't clip past
    # plot_x1). Node A's rect: (60,20,12,230); node B's rect:
    # (368,20,12,230) -- both fill the plot's full height (the
    # only node in their column). The ribbon fills the gap
    # between them, (72,20)-(72,250)-(368,250)-(368,20), colored by
    # its "from" node (A) (see this file's SVG test).
    var from_c: List[String] = ["A"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [10.0]
    var _hoisted1 = sankey(from_c, to_c, v, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 66, 135, palette[0], "node A's rect")
    _assert_color(c, 220, 135, palette[0], "the ribbon, well inside its bounds")
    _assert_color(c, 374, 135, palette[1], "node B's rect")


def test_render_sankey_svg_matches_confirmed_geometry() raises:
    var from_c: List[String] = ["A"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [10.0]
    var plot = Plot().mark_sankey().encode_chord(from_categories=from_c, to_categories=to_c, values=v).theme(
        Theme()
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M72.000,20.000 L72.000,250.000 L368.000,250.000 L368.000,20.000 Z" fill="#1f77b4"/>' in s,
        "the ribbon, A's column edge to B's column edge",
    )
    assert_true('<rect x="60" y="20" width="12" height="230" fill="#1f77b4"/>' in s, "node A")
    assert_true('<rect x="368" y="20" width="12" height="230" fill="#ff7f0e"/>' in s, "node B")


def test_render_sankey_skip_edge_routes_through_a_pass_through_node() raises:
    # A->B (col0->col1), B->C (col1->col2), and D->C directly (col0->
    # col2, a skip edge -- gap 2) -- every value 10, so every node/
    # pass-through node splits its column exactly in half. Canvas
    # 400x300, same no-legend plot area (x:[60,380], y:[20,250]) and
    # column x positions (60/214/368 for 3 columns, node width 12) the
    # 2-column test above derives, extended to a third column.
    #
    # Column 0 members in node-index order (A=0, D=2): A gets the top
    # half (y 20-135), D the bottom half (135-250). Column 1 members
    # (B=1, then D's pass-through node, appended after every real
    # node): B gets the top half, the pass-through node the bottom
    # half -- competing for column-1 space exactly like a real node,
    # even though it draws no bar. Column 2 has only C,
    # spanning the full height.
    #
    # Ribbons: A->B fills column0-1's top half (blue, A's color); B->C fills column1-2's top half (orange); D's skip edge becomes two chained segments, D->pass-through
    # (column0-1's bottom half) and pass-through->C (column1-2's
    # bottom half), *both* colored green (D's color, the
    # flow's original source) even though the second segment's immediate `from` is the invisible pass-through node, not D
    # itself.
    var from_c: List[String] = ["A", "B", "D"]
    var to_c: List[String] = ["B", "C", "C"]
    var v: List[Float64] = [10.0, 10.0, 10.0]
    var _hoisted2 = sankey(from_c, to_c, v, width=400, height=300)
    var c = render(_hoisted2)

    var palette = default_categorical_palette()
    _assert_color(c, 66, 77, palette[0], "node A's rect (column 0, top half)")
    _assert_color(c, 66, 192, palette[2], "node D's rect (column 0, bottom half)")
    _assert_color(c, 220, 77, palette[1], "node B's rect (column 1, top half)")
    _assert_color(c, 374, 135, palette[3], "node C's rect (column 2, full height)")
    _assert_color(c, 143, 77, palette[0], "A->B ribbon, column 0-1 gap, top half")
    _assert_color(c, 297, 77, palette[1], "B->C ribbon, column 1-2 gap, top half")
    _assert_color(
        c, 143, 192, palette[2], "D's skip edge, first segment (D -> pass-through), still D's color"
    )
    _assert_color(
        c, 297, 192, palette[2], "D's skip edge, second segment (pass-through -> C), still D's color"
    )
    # The one point that actually distinguishes this from a version
    # with no pass-through node at all: (220, 192) sits inside column
    # 1's node-width strip (x 214-226), in its bottom half -- the
    # pass-through node's reserved slot. Nothing draws there (no
    # bar for an invisible pass-through node, and neither ribbon
    # segment crosses the node-width gap itself) -- background.
    # Without that reserved slot, D's skip edge would draw as one
    # straight ribbon and B's bar -- the column's only "real" member --
    # would claim the *entire* column height instead of just its top
    # half, painting orange here instead of background.
    _assert_color(c, 220, 192, BG, "the pass-through node's reserved slot -- background, not node B's bar")


def test_render_sankey_raises_on_cycle() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B", "A"]
    var v: List[Float64] = [5.0, 5.0]
    with assert_raises():
        var _hoisted3 = sankey(from_c, to_c, v, width=200, height=150)
        _ = render(_hoisted3)


def test_render_sankey_self_loop_doesnt_raise() raises:
    var from_c: List[String] = ["A", "A"]
    var to_c: List[String] = ["A", "B"]
    var v: List[Float64] = [5.0, 5.0]
    var _hoisted4 = sankey(from_c, to_c, v, width=200, height=150)
    var c = render(_hoisted4)
    _ = c


def test_render_sankey_raises_on_negative_value() raises:
    var from_c: List[String] = ["A"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [-1.0]
    with assert_raises():
        var _hoisted5 = sankey(from_c, to_c, v, width=200, height=150)
        _ = render(_hoisted5)


def test_render_sankey_raises_on_mismatched_length() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted6 = sankey(from_c, to_c, v, width=200, height=150)
        _ = render(_hoisted6)


def test_render_sankey_empty_data_only_fills_background() raises:
    var from_c = List[String]()
    var to_c = List[String]()
    var v = List[Float64]()
    var _hoisted7 = sankey(from_c, to_c, v, width=100, height=80)
    var c = render(_hoisted7)
    _assert_color(c, 50, 40, BG, "no edges: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
