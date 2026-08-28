"""Generic Plot.encode()/render() validation and utility-function tests
that aren't specific to any one Mark type.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
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
    _categorical_indices,
    _decimate_to_pixel_columns,
    _index_of,
    _unique_categories,
)
from dataviz_mojo.edges import _edge_node_index
from dataviz_mojo.theme import Theme
from dataviz_mojo import scatter
from dataviz_mojo.colors import RED

from _test_helpers import _count_color, _assert_color


def test_render_raises_on_mismatched_x_y_lengths() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0]
    var plot = Plot().encode(x=x, y=y).size(200, 150)
    with assert_raises():
        var c = render(plot)


def test_render_empty_data_only_fills_background() raises:
    # render() always fills with theme.background regardless of
    # whatever the canvas was constructed with (Plot owns the whole
    # canvas it's given -- see plot.mojo's docstring), so the
    # canvas's initial fill color (10,20,30) must NOT survive.
    var plot = Plot().size(50, 40)  # no encode() call -- x_data/y_data both empty
    var c = render(plot)
    var expected = Theme.default().background
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, expected.r)
            assert_equal(p.g, expected.g)
            assert_equal(p.b, expected.b)


def test_render_respects_custom_theme_colors() raises:
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var custom = Theme(background=Color(20, 20, 20), mark_color=RED)
    var _hoisted1 = scatter(x, y, theme=custom, width=400, height=300)
    var c = render(_hoisted1)

    # Far corner, untouched by any mark/axis/gridline -- pure background.
    var corner = c.get_pixel(399, 0)
    assert_equal(corner.r, 20)
    assert_equal(corner.g, 20)
    assert_equal(corner.b, 20)

    var mark_pixel = c.get_pixel(220, 135)
    assert_equal(mark_pixel.r, 255)
    assert_equal(mark_pixel.g, 0)
    assert_equal(mark_pixel.b, 0)


def test_render_gridlines_flag_actually_controls_gridline_pixels() raises:
    # Built via Plot/Canvas/render() directly, not scatter() -- an
    # exact-zero pixel count is sensitive to any anti-aliasing detail,
    # and this test predates quickplot returning a plain, un-rendered
    # `Plot` (dataviz_mojo.plot._finished's docstring); render() is
    # the exact same path scatter()'s own output would go through now
    # too, so this check would hold identically either way.
    #
    # The "off" side no longer asserts an exact 0: `render()`'s
    # supersample-then-downsample (`_RASTER_SUPERSAMPLE`, plot.mojo)
    # can blend an unrelated edge (a tick mark, a label glyph, the
    # point marker's own AA fringe) to coincidentally land on this
    # exact gray by chance, a handful of times, with no gridlines
    # drawn at all -- see `_assert_near_color`'s docstring (tests/
    # _test_helpers.mojo) for the same underlying phenomenon. What
    # still holds exactly: real gridlines paint this color at a whole
    # different order of magnitude more pixels (hundreds, from long
    # straight runs) than stray incidental collisions ever could (a
    # handful) -- so the flag's actual effect is checked by that gap,
    # not by a brittle exact zero.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var gridline_color = Color(225, 225, 225)

    var _hoisted2 = Plot().mark_point().encode(x=x, y=y).theme(Theme(show_gridlines=True)).size(400, 300)
    var c_on = render(_hoisted2)
    var count_on = _count_color(c_on, gridline_color)
    assert_true(count_on > 0)

    var _hoisted3 = Plot().mark_point().encode(x=x, y=y).theme(Theme(show_gridlines=False)).size(400, 300)
    var c_off = render(_hoisted3)
    var count_off = _count_color(c_off, gridline_color)
    assert_true(
        count_off * 10 < count_on,
        "far fewer gridline-colored pixels with gridlines off (" + String(count_off) + ") than on ("
        + String(count_on) + ")",
    )


def test_render_raises_on_mismatched_color_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var color: List[Float64] = [1.0, 2.0]
    var plot = Plot().encode(x=x, y=y, color=color).size(200, 150)
    with assert_raises():
        var c = render(plot)


def test_render_raises_on_mismatched_size_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var size: List[Float64] = [1.0, 2.0]
    var plot = Plot().encode(x=x, y=y, size=size).size(200, 150)
    with assert_raises():
        var c = render(plot)


def test_unique_categories_preserves_first_seen_order() raises:
    var data: List[String] = ["b", "a", "b", "c", "a"]
    var unique = _unique_categories(data)
    assert_equal(len(unique), 3)
    assert_equal(unique[0], "b")
    assert_equal(unique[1], "a")
    assert_equal(unique[2], "c")


def test_categorical_indices_agrees_with_unique_categories_and_index_of() raises:
    # _categorical_indices replaces a _unique_categories pass plus a
    # per-point _index_of search with one hashed pass. Its whole
    # contract is that it produces exactly what those two did, so this
    # asserts equivalence against both directly rather than against
    # hand-written expected values -- if the fast path ever disagrees
    # with the slow one it's wrong by definition.
    var data: List[String] = ["b", "a", "b", "c", "a", "c", "c"]
    var cat = _categorical_indices(data)

    var expected_domain = _unique_categories(data)
    assert_equal(len(cat.domain), len(expected_domain))
    for i in range(len(expected_domain)):
        assert_equal(cat.domain[i], expected_domain[i])

    assert_equal(len(cat.indices), len(data))
    for i in range(len(data)):
        assert_equal(cat.indices[i], _index_of(expected_domain, data[i]))
        # .and the index really does address the right category.
        assert_equal(cat.domain[cat.indices[i]], data[i])


def test_edge_node_index_agrees_with_unique_categories_and_index_of() raises:
    # _edge_node_index replaces exactly what Mark.CHORD/ARC_DIAGRAM/
    # GRAPH/SANKEY each did by hand: _unique_categories over the two
    # endpoint columns concatenated, then _index_of per endpoint per
    # edge. Same contract as _categorical_indices' equivalence
    # test above -- assert against the slow path directly, not against
    # hand-written values, since disagreeing with it is the definition
    # of being wrong.
    var f: List[String] = ["b", "a", "c", "a"]
    var t: List[String] = ["a", "c", "b", "d"]
    var edges = _edge_node_index(f, t)

    var combined = List[String]()
    for v in f:
        combined.append(v)
    for v in t:
        combined.append(v)
    var expected_nodes = _unique_categories(combined)

    # First-seen order across both columns, `from` first -- the order
    # every node's palette color and ring position depends on.
    assert_equal(len(edges.nodes), len(expected_nodes))
    for i in range(len(expected_nodes)):
        assert_equal(edges.nodes[i], expected_nodes[i])

    assert_equal(len(edges.from_idx), len(f))
    assert_equal(len(edges.to_idx), len(t))
    for i in range(len(f)):
        assert_equal(edges.from_idx[i], _index_of(expected_nodes, f[i]))
        assert_equal(edges.to_idx[i], _index_of(expected_nodes, t[i]))
        # .and each index really does address the right node.
        assert_equal(edges.nodes[edges.from_idx[i]], f[i])
        assert_equal(edges.nodes[edges.to_idx[i]], t[i])


def test_edge_node_index_handles_a_node_only_appearing_as_a_target() raises:
    # "d" above appears only in the `to` column -- the case a naive
    # split that indexed only the `from` column would miss entirely.
    var f: List[String] = ["a"]
    var t: List[String] = ["b"]
    var edges = _edge_node_index(f, t)
    assert_equal(len(edges.nodes), 2)
    assert_equal(edges.nodes[0], "a")
    assert_equal(edges.nodes[1], "b")
    assert_equal(edges.from_idx[0], 0)
    assert_equal(edges.to_idx[0], 1)


def test_decimate_declines_when_points_are_individually_resolvable() raises:
    # 4 points spread over ~100 pixel columns: far below the 2-per-
    # column budget, so nothing is dropped and the path is byte-for-
    # byte what it always was. This is the case every chart in this
    # suite is in, which is why none of their pixel assertions moved.
    var px: List[Float64] = [0.0, 30.0, 60.0, 90.0]
    var py: List[Float64] = [10.0, 20.0, 15.0, 25.0]
    var d = _decimate_to_pixel_columns(px, py)
    assert_equal(d.applied, False)
    assert_equal(len(d.px), 4)
    for i in range(4):
        assert_equal(d.px[i], px[i])
        assert_equal(d.py[i], py[i])


def test_decimate_declines_on_a_non_monotonic_path() raises:
    # mark_line() connects points in data order, never sorted by x, so
    # a path that doubles back is legitimate -- and grouping it by
    # pixel column would reorder the drawing into a different shape.
    # 10 points all inside one column, so the density guard alone would
    # not have saved it: the monotonic check is what declines here.
    var px = List[Float64]()
    var py = List[Float64]()
    for i in range(10):
        px.append(0.5 if i % 2 == 0 else 0.2)
        py.append(Float64(i))
    var d = _decimate_to_pixel_columns(px, py)
    assert_equal(d.applied, False)
    assert_equal(len(d.px), 10)


def test_decimate_keeps_both_extremes_of_each_column() raises:
    # 12 points across 3 pixel columns (0, 1, 2), 4 per column -- above
    # the 2-per-column budget, so decimation engages. Column 1 holds a
    # spike: y runs 5, 99, 1, 5. Hand-derived expectation: that column
    # contributes exactly its max (99, at index 5) and its min (1, at
    # index 6), in that data order -- so the spike survives at full
    # height instead of being flattened to whatever the column's first
    # point happened to be.
    var px = List[Float64]()
    var py = List[Float64]()
    var ys: List[Float64] = [5.0, 6.0, 7.0, 8.0, 5.0, 99.0, 1.0, 5.0, 4.0, 3.0, 2.0, 1.5]
    for i in range(12):
        px.append(Float64(i // 4))
        py.append(ys[i])
    var d = _decimate_to_pixel_columns(px, py)
    assert_equal(d.applied, True)

    # 3 columns x at most 2 points each.
    assert_equal(len(d.px), 6)
    assert_equal(len(d.py), 6)

    # Column 0: ys 5,6,7,8 -> min 5 (index 0), max 8 (index 3), data
    # order gives 5 then 8.
    assert_equal(d.px[0], 0.0)
    assert_equal(d.py[0], 5.0)
    assert_equal(d.py[1], 8.0)

    # Column 1: the spike, max 99 before min 1 in data order.
    assert_equal(d.px[2], 1.0)
    assert_equal(d.py[2], 99.0)
    assert_equal(d.px[3], 1.0)
    assert_equal(d.py[3], 1.0)

    # Column 2: ys 4, 3, 2, 1.5 -> strictly descending, so the max
    # (4.0, index 8) comes first in data order and the min (1.5, index
    # 11) last.
    assert_equal(d.px[4], 2.0)
    assert_equal(d.py[4], 4.0)
    assert_equal(d.py[5], 1.5)


def test_decimate_collapses_a_flat_column_to_one_point() raises:
    # 8 points over 2 columns, every y identical: min and max are the
    # same sample, so each column emits one point, not two.
    var px = List[Float64]()
    var py = List[Float64]()
    for i in range(8):
        px.append(Float64(i // 4))
        py.append(7.0)
    var d = _decimate_to_pixel_columns(px, py)
    assert_equal(d.applied, True)
    assert_equal(len(d.px), 2)
    assert_equal(d.py[0], 7.0)
    assert_equal(d.py[1], 7.0)


def test_categorical_indices_on_an_empty_column_is_empty() raises:
    # The unencoded-channel case _PointChannels takes when no
    # categorical color column was given.
    var cat = _categorical_indices(List[String]())
    assert_equal(len(cat.domain), 0)
    assert_equal(len(cat.indices), 0)


def test_index_of_finds_positions_and_reports_missing_as_negative_one() raises:
    var data: List[String] = ["x", "y", "z"]
    assert_equal(_index_of(data, "x"), 0)
    assert_equal(_index_of(data, "z"), 2)
    assert_equal(_index_of(data, "q"), -1)


def test_render_raises_when_color_and_color_categories_both_given() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var color: List[Float64] = [1.0, 2.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().encode(x=x, y=y, color=color, color_categories=cats).size(200, 150)
    with assert_raises():
        var c = render(plot)


def test_render_raises_on_mismatched_color_categories_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().encode(x=x, y=y, color_categories=cats).size(200, 150)
    with assert_raises():
        var c = render(plot)


def test_render_svg_raises_on_mismatched_x_y_lengths() raises:
    # render_svg()'s validation isn't a separate check -- it's the
    # exact same _render_generic core render() itself calls, so a
    # mismatched-length Plot raises through either entry point
    # identically. Confirms that sharing, not re-derives the check.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0]
    var plot = Plot().encode(x=x, y=y).size(200, 150)
    with assert_raises():
        var svg = render_svg(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
