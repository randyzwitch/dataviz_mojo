"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers Mark.SUNBURST, Mark.TREE, and
Mark.TREEMAP (with encode_hierarchy()'s shared validation), and
Mark.CHORD, Mark.ARC_DIAGRAM, Mark.GRAPH, and Mark.SANKEY (with
encode_chord()'s shared validation), each raster + SVG.
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
    # root -> A (50%) -> A1/A2 (50/50); root -> B (50%) -> B1 (B's only
    # child). Canvas 400x300, no legend: plot area x:[60,380], y:[20,250]
    # -> center (220,135), max radius 103.5. max_depth=2 -> ring_width
    # 51.75: ring 1 spans [0,51.75], ring 2 [51.75,103.5].
    #
    # A spans -90..90 degrees (bisector 0, east); B spans 90..270
    # (bisector 180, west). A1 spans -90..0 (bisector -45); A2 spans 0..90
    # (bisector 45); B1 spans B's full 90..270. Every sample point sits at
    # a radius safely inside its ring.
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


def test_render_sunburst_raises_on_no_data() raises:
    # #206: an empty hierarchy used to render a plain background with no
    # error; _build_hierarchy_index's existing "no root found" raise now
    # actually fires (the render-time empty guard used to intercept it
    # first and return a blank result instead).
    var ids = List[String]()
    var parents = List[String]()
    var values = List[Float64]()
    with assert_raises():
        var _hoisted9 = sunburst(ids, parents, values, width=100, height=80)
        _ = render(_hoisted9)


def test_render_sunburst_raises_on_a_cycle() raises:
    # "a" and "b" are each other's parent: every other check passes, and
    # without the reachability check both rows would silently vanish,
    # taking 16 of the 21 total value.
    var ids: List[String] = ["root", "leaf", "a", "b"]
    var parents: List[String] = ["", "root", "b", "a"]
    var values: List[Float64] = [0.0, 5.0, 7.0, 9.0]
    with assert_raises():
        var _hoisted10 = sunburst(ids, parents, values, width=200, height=150)
        _ = render(_hoisted10)


def test_render_sunburst_raises_on_a_disconnected_component() raises:
    # A self-parented row ("orphan" is its own parent) resolves but is
    # never reachable; the one-node case of the same check.
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
    # root -> A, B (both leaves): 2 leaves, max_depth 1. Canvas 400x300, no
    # legend: plot area x:[60,380], y:[20,250]. A's slot 0 maps to 60, B's
    # slot 1 to 380, root's slot 0.5 to 220; depth 0 maps to 20, depth 1
    # to 250.
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
    # A point on the root->A edge clear of both markers: 25% along from
    # (220,20) to (60,250) is (180, 77.5); y=77.5 sits on a row boundary
    # that AA-blends at y=78, so y=77 lands solidly on the stroke.
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


def test_render_tree_raises_on_no_data() raises:
    # #206: see test_render_sunburst_raises_on_no_data above.
    var ids = List[String]()
    var parents = List[String]()
    var values = List[Float64]()
    with assert_raises():
        var _hoisted5 = tree(ids, parents, values, width=100, height=80)
        _ = render(_hoisted5)

# ---------------------------------------------------------------
# from tests/test_treemap.mojo
# ---------------------------------------------------------------

def test_render_treemap_matches_hand_derived_rects() raises:
    # root -> A (total 30: A1=20, A2=10), root -> B (total 10: B1=10).
    # Canvas 400x300, no legend: plot area x:[60,380], y:[20,250]. Depth 0
    # splits along x: A gets 75% of 320 = 240px, x:[60,300]; B gets
    # x:[300,380]. Depth 1 splits along y: A1 gets 66.7% of 230 = 153px,
    # y:[20,173]; A2 gets y:[173,250]. B1 gets B's rect unchanged.
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


def test_render_treemap_raises_on_no_data() raises:
    # #206: see test_render_sunburst_raises_on_no_data above.
    var ids = List[String]()
    var parents = List[String]()
    var values = List[Float64]()
    with assert_raises():
        var _hoisted6 = treemap(ids, parents, values, width=100, height=80)
        _ = render(_hoisted6)

# ---------------------------------------------------------------
# from tests/test_chord.mojo
# ---------------------------------------------------------------

def test_render_chord_two_nodes_one_edge_matches_hand_derived_geometry() raises:
    # 2 nodes, one edge A->B, value 10: each node's total flow is 10, so
    # the two ring sectors split the circle in half (A: -pi/2..pi/2, B:
    # pi/2..3pi/2). Canvas 400x300, no legend: plot area x:[60,380],
    # y:[20,250], center (220,135), radius 103.5, inner_radius =
    # 103.5*0.92 = 95.22.
    #
    # With one edge, its sub-arcs are each node's full span, so the
    # ribbon's rim segments trace A's entire rim then B's, a full circle
    # at inner_radius, with both cross curves degenerating to a point.
    # Filling that path fills the entire inner disk in the ribbon's color
    # (A's, palette index 0), so the inner-disk sample on B's side is still
    # palette[0].
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
    # A structural check (a curved multi-segment path isn't practically
    # hand-derived): three nodes with real flows produce <path> markup for
    # both the ribbons and the ring sectors.
    var from_cats: List[String] = ["A", "B"]
    var to_cats: List[String] = ["B", "C"]
    var values: List[Float64] = [5.0, 3.0]
    var plot = Plot().mark_chord().encode_chord(
        from_categories=from_cats, to_categories=to_cats, values=values
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true("<path " in s, "at least one ribbon drawn as a real SVG path")
    # default_categorical_palette()'s first three entries:
    # (31,119,180)/(255,127,14)/(44,160,44).
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


def test_render_chord_raises_on_no_data() raises:
    # #206: an empty edge list used to render a plain background with no
    # error; _validate_edge_encoding now raises before any layout.
    var from_cats = List[String]()
    var to_cats = List[String]()
    var values = List[Float64]()
    with assert_raises():
        var _hoisted5 = chord(from_cats, to_cats, values, width=200, height=150)
        _ = render(_hoisted5)

# ---------------------------------------------------------------
# from tests/test_arc_diagram.mojo
# ---------------------------------------------------------------

def test_render_arc_diagram_matches_hand_derived_arcs() raises:
    # 3 nodes (A, B, C in first-seen order), edges A->B (value 10, the max)
    # and B->C (value 5). Canvas 400x300, default theme: plot area
    # x:[60,380], y:[20,250] -> nodes at x=60/220/380 on the baseline
    # y=250.
    #
    # Edge A->B: center (140,250), radius 80, peak (140,170). Edge B->C:
    # center (300,250), radius 80, peak (300,170). Widths: A->B at frac
    # 1.0 -> 6; B->C at frac 0.5 -> 4 (asserted in the SVG test).
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
    # No raise means the self-loop (A->A) was skipped rather than crashing
    # on a zero-diameter arc.
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


def test_render_arc_diagram_raises_on_no_data() raises:
    # #206: see test_render_chord_raises_on_no_data above.
    var from_c = List[String]()
    var to_c = List[String]()
    var v = List[Float64]()
    with assert_raises():
        var _hoisted5 = arc_diagram(from_c, to_c, v, width=100, height=80)
        _ = render(_hoisted5)

# ---------------------------------------------------------------
# from tests/test_graph.mojo
# ---------------------------------------------------------------

def test_render_graph_matches_hand_derived_edges() raises:
    # 3 nodes (A, B, C), edges A->B (value 10, the max) and B->C (value 5).
    # Canvas 400x300, default theme: plot area x:[60,380], y:[20,250] ->
    # center (220,135), max radius 103.5. Nodes evenly spaced from 12
    # o'clock clockwise: A at -90 degrees -> (220,32); B at 30 -> (310,187);
    # C at 150 -> (130,187). Edge midpoints confirm each edge's color
    # follows its `from` node.
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


def test_render_graph_raises_on_no_data() raises:
    # #206: see test_render_chord_raises_on_no_data above.
    var from_c = List[String]()
    var to_c = List[String]()
    var v = List[Float64]()
    with assert_raises():
        var _hoisted5 = graph(from_c, to_c, v, width=100, height=80)
        _ = render(_hoisted5)

# ---------------------------------------------------------------
# from tests/test_sankey.mojo
# ---------------------------------------------------------------

def test_render_sankey_matches_hand_derived_nodes_and_ribbon() raises:
    # 2 nodes, one edge A->B (value 10, both nodes' entire flow). Canvas
    # 400x300, default theme: plot area x:[60,380], y:[20,250]. 2 columns,
    # node width 12, column x positions 60 and 368 (the last column pulled
    # in by one node width). Node A's rect: (60,20,12,230); node B's:
    # (368,20,12,230). The ribbon fills (72,20)-(72,250)-(368,250)-(368,20)
    # in A's color.
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
    # A->B, B->C, and D->C directly (a skip edge, gap 2), every value 10,
    # so every node/pass-through splits its column in half. Canvas
    # 400x300, plot area x:[60,380], y:[20,250], column x positions
    # 60/214/368, node width 12.
    #
    # Column 0 (A, D): A gets the top half (y 20-135), D the bottom.
    # Column 1 (B, then D's pass-through node): B top, pass-through bottom.
    # Column 2: C, full height.
    #
    # Ribbons: A->B fills column 0-1's top half (blue); B->C fills column
    # 1-2's top half (orange); D's skip edge becomes D->pass-through
    # (column 0-1's bottom half) and pass-through->C (column 1-2's bottom
    # half), both green (D's color).
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
    # The one point that distinguishes this from a version with no
    # pass-through node: (220, 192) sits in column 1's node-width strip (x
    # 214-226), bottom half, the pass-through node's slot. Nothing draws
    # there. Without the reserved slot, B's bar would claim the whole
    # column height and paint orange here.
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


def test_render_sankey_raises_on_no_data() raises:
    # #206: see test_render_chord_raises_on_no_data above.
    var from_c = List[String]()
    var to_c = List[String]()
    var v = List[Float64]()
    with assert_raises():
        var _hoisted7 = sankey(from_c, to_c, v, width=100, height=80)
        _ = render(_hoisted7)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
