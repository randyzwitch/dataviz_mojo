"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_core.mojo`: Generic Plot.encode()/render() validation and utility-function tests
  that aren't specific to any one Mark type.

- `test_margins.mojo`: Tests for the dynamic left-margin computation (wide y-axis tick labels
  growing plot_x0 on both the continuous and Mark.BAR render paths).
  
  The axis-line-position checks use `_assert_near_color()`, not
  `_assert_color()` -- `render()`'s supersample-then-downsample
  (`_RASTER_SUPERSAMPLE`, plot.mojo) has no single output pixel that
  lands fully opaque for a 1px-wide stroke, so an exact color match at
  the line's own nominal column isn't guaranteed the way a filled mark's
  solid interior pixel still is (see `_assert_near_color`'s own
  docstring, tests/_test_helpers.mojo). What's still checked exactly:
  *which* column the line's ink concentrates around (the margin
  actually moved), not the precise color at it.

- `test_labels.mojo`: Tests for Plot.labels(): title/subtitle/axis-title rendering and
  positioning (raster + SVG), including precise centering on the legend-
  narrowed inner plot rect.

- `test_theme.mojo`: Tests for Theme.scale (uniform layout scaling and its purely-additive
  default), Theme.font_family (threaded into every _TextRequest at
  construction time, both backends), and Theme.title_bold (the one
  Theme default that isn't backward-compatible).

- `test_legends.mojo`: Tests for categorical/continuous legends: swatch positions, continuous
  color/size legends, dynamic legend-column width.

- `test_marker.mojo`: Tests for `PointShape`/`Theme.shape_by_category`: the fixed shape
  cycle itself, exact per-shape render geometry (SVG), legend swatch
  integration, and the "no-op without `color_categories`" precedent
  `Theme.color_by_sign` already sets for a comparable mismatch.

- `test_svg_accessibility.mojo`: Tests for accessible_svg_string()/write_accessible_svg(): the
  role="img"/aria-label root attributes, the <title>/<desc> leading
  child elements (and <desc>'s omission when description is empty),
  XML-escaping of special characters in both, and that the chart's already-rendered body is preserved unchanged underneath the new markup.

"""

from _test_helpers import BG, _assert_color, _assert_near_color, _count_color, _index_of, _unique_categories
from canvas.color import Color
from canvas.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from dataviz import (
    PointShape,
    bar,
    beeswarm,
    box,
    bullet,
    default_marker_shapes,
    line,
    pie,
    radialbar,
    scatter,
    treemap,
    waterfall,
)
from dataviz.color_scale import default_categorical_palette
from dataviz.colors import RED
from dataviz.edges import _edge_node_index
from dataviz.plot import (
    Plot,
    accessible_svg_string,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    _Scaled,
    _build_line_path,
    _categorical_indices,
    _decimate_to_pixel_columns,
)
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_core.mojo
# ---------------------------------------------------------------

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
    # `Plot` (dataviz.plot._finished's docstring); render() is
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

# ---------------------------------------------------------------
# from tests/test_margins.mojo
# ---------------------------------------------------------------

def test_render_left_margin_grows_to_fit_wide_y_axis_labels() raises:
    # y=[1000000,2000000] gives nice ticks [1000000,1500000,2000000]
    # (_data_extent pads to domain [950000,2050000]; Heckbert's
    # nice-step algorithm picks step=500000 for that span -- same
    # hand-verified math test_scale.mojo's tests lock in, not
    # re-derived here). Those three labels' rendered width at the
    # default 12pt font, against this environment's real "Sans" font
    # metrics (unhinted, so glyph widths depend on the installed font
    # file), maxes out at 51.8px (the "2000000" label).
    # dynamic_left_margin = Int(51.8) + theme.tick_length(5) +
    # theme.label_gap(4) + theme.margin_buffer(8) = 68, wider than
    # Theme's default 60px margin, so plot_x0 becomes 68, not 60 -- checked
    # directly against where the y-axis line itself actually is (drawn
    # at exactly plot_x0), not an indirect proxy for it.
    # Built via Plot/Canvas/render() directly, not scatter() -- these
    # margin/axis-line pixel positions are exact by construction (see
    # this function's comment above); this test predates quickplot
    # returning a plain, un-rendered `Plot` (dataviz.plot.
    # _finished's docstring), render() being the exact same path
    # scatter()'s own output would go through now too.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [1000000.0, 2000000.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = Plot().mark_point().encode(x=x, y=y).theme(t).size(400, 300)
    var c = render(_hoisted1)

    _assert_near_color(c, 68, 135, t.axis_color, 70, "y-axis line moved to the dynamic margin")

    # The wide label's ink extends left of a plain fixed 60px margin:
    # real, non-background pixels sit at x=57, part of the
    # "2000000" label's glyphs (x=56 itself is a gap between glyphs).
    # A plain "x=60 is
    # background" check would be wrong here, since covering that space
    # with real label ink is the entire point of this feature, not an
    # absence to assert on.
    var left_of_old_margin = c.get_pixel(57, 135)
    assert_true(
        left_of_old_margin.r != 255 or left_of_old_margin.g != 255 or left_of_old_margin.b != 255,
        "wide tick label's ink reaches left of the plain fixed margin",
    )


def test_render_left_margin_unchanged_for_short_y_axis_labels() raises:
    # Confirms the dynamic computation is purely additive: short
    # labels ("2","4","6","8","10", from the same data every other
    # point-mark test in this file uses) must leave plot_x0 at
    # exactly Theme's default 60, byte-identical to every other
    # hand-derived test above -- the same margin every one of those
    # depends on for its hand-derived pixel math to hold.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]
    var t = Theme(show_gridlines=False)
    var _hoisted2 = Plot().mark_point().encode(x=x, y=y).theme(t).size(400, 300)
    var c = render(_hoisted2)

    _assert_near_color(c, 60, 135, t.axis_color, 70, "y-axis line still at Theme's default margin")


def test_render_bar_left_margin_also_grows_to_fit_wide_y_axis_labels() raises:
    # Same dynamic-left-margin mechanism as the continuous-path tests
    # above, wired into _render_bar independently (see that
    # function's comment) -- a separate function, not shared code.
    # y=[1000000,2000000] through _zero_baseline_y_extent (BAR's
    # always-include-zero y-domain, not _data_extent's) gives nice
    # ticks [0,500000,1000000,1500000,2000000], which lands on the
    # identical dynamic_left_margin=68 the continuous-path test above
    # got (the widest
    # label's width happens to match closely enough that both round to
    # the same margin), so the same pixel checks apply: the y-axis
    # line at x=68, and real label ink reaching left of a plain fixed
    # 60px margin (x=57, coinciding with the continuous test's x=57
    # too).
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1000000.0, 2000000.0]
    var t = Theme(show_gridlines=False)
    var _hoisted3 = Plot().mark_bar().encode_categorical(x=x, y=y).theme(t).size(400, 300)
    var c = render(_hoisted3)

    _assert_near_color(c, 68, 135, t.axis_color, 70, "bar chart y-axis line moved to the dynamic margin")
    var left_of_old_margin = c.get_pixel(57, 135)
    assert_true(
        left_of_old_margin.r != 255 or left_of_old_margin.g != 255 or left_of_old_margin.b != 255,
        "wide tick label's ink reaches left of the plain fixed margin",
    )

# ---------------------------------------------------------------
# from tests/test_labels.mojo
# ---------------------------------------------------------------

def test_render_svg_labels_matches_hand_derived_title_and_axis_titles() raises:
    # Same x=[0,10]/y=[5,5] data as the plain-LINE SVG test just above,
    # now with all three of Plot.labels()'s strings set -- default
    # Theme (title_font_size=18.0, axis_title_font_size=14.0,
    # label_gap=4), canvas 400x300, show_gridlines=False.
    #
    # _apply_labels reserves extra_top=Int(18.0)+4=22, extra_bottom=
    # Int(14.0)+4=18, extra_left=Int(14.0)+4=18 from the *outer* 400x300
    # bounds before _render_generic ever runs, so the inner rect handed
    # to it is (18, 22, 400, 282), not (0, 0, 400, 300) -- shifting
    # every plot-area/tick/line-endpoint coordinate the original LINE
    # SVG test hand-solved for the unshrunk canvas. Every position below
    # (titles' anchors, and the line's re-solved endpoints)
    # independently re-derived via python3 from that shrunk rect.
    #
    # Title/x_title/y_title all center on the *inner* plot rect
    # (_RenderResult's px0/py0/px1/py1 -- see the wiki's Changelog,
    # its "Plot.labels() precise centering" entry), not the full
    # outer bounds -- confirmed here via the LINE mark's already-
    # hand-solved endpoints just below: plot_x0=78 (frame.ox0=18 +
    # margin_left=60, no dynamic left-margin growth -- short y=5 tick
    # labels), plot_x1=380 (frame.ox1=400 - margin_right=20, no legend
    # on Mark.LINE), matching the line path's re-solved
    # to_pixel(0)=91.727/to_pixel(10)=366.273 (slope solved from those
    # two points) below.
    #
    # plot_y0=42 (frame.oy0=22 + margin_top=20),
    # plot_y1=232 (frame.oy1=282 - margin_bottom=50) -- matching the
    # line's flat y=137.000 (the exact vertical midpoint, y=[5,5]
    # constant data).
    #
    # Title: center=((78+380)//2, 14)=(229,14) -- horizontal center is
    # the inner rect's, but the *vertical* position (14) still comes
    # from the *original* outer oy0=0 (Int(18.0*0.8)=14), unaffected --
    # only the cross-axis coordinate moved, not the along-axis one (see
    # _label_text_requests' docstring). No rotation (0.0, so no
    # transform attr).
    # x_title: center=(229,297) -- same horizontal center as title,
    # vertical position still from the original outer oy1=300
    # (300-Int(14.0*0.25)=297), unaffected.
    # y_title: (11,(42+232)//2)=(11,137) -- horizontal position still
    # from the original outer ox0=0 (Int(14.0*0.8)=11), unaffected; the
    # *vertical* center is the inner rect's (137), not derived from
    # outer bounds (which would give 150) -- rotation=-pi/2 -> exactly
    # -90.000 degrees (bottom-to-top reading, the standard y-axis-title
    # convention).
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .labels(title="My Title", x_title="X Axis", y_title="Y Axis")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true(
        '<text x="229" y="14" font-size="18.000" font-family="sans-serif" font-weight="bold" fill="#282828"'
        ' text-anchor="middle">My Title</text>' in s,
        "chart title -- centered over the inner plot rect, no rotation",
    )
    assert_true(
        '<text x="229" y="297" font-size="14.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">X Axis</text>' in s,
        "x_title -- centered over the inner plot rect, near the bottom edge",
    )
    assert_true(
        '<text x="11" y="137" font-size="14.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle" transform="rotate(-90.000 11 137)">Y Axis</text>' in s,
        "y_title -- rotated -90 degrees (reads bottom-to-top), vertically centered on the inner rect",
    )
    assert_true(
        '<path d="M91.727,137.000 L366.273,137.000" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>' in s,
        "the LINE mark itself, re-solved against the shrunk inner rect",
    )


def test_render_svg_title_centers_on_inner_plot_rect_not_outer_bounds() raises:
    # A title must center on the *inner* plot rect, not the full outer
    # canvas -- same long-category-name legend setup as test_render_
    # point_legend_width_grows_to_fit_long_category_names above
    # (_dynamic_legend_width=166, plot_x1=400-20-166=214; plot_x0 stays
    # the default margin_left=60 -- y=[0.0,0.0] pads to a short-labeled
    # domain, no dynamic-left-margin growth here), now with a chart
    # title too. The title centers at (60+214)//2=137 -- correctly
    # shifted left of the legend-narrowed data area's true center, not
    # the legend-oblivious canvas center's ((0+400)//2=200).
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["Cat1", "Southeast Region Sales"]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cats)
        .labels(title="Sales by Region")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="137" y="14" font-size="18.000" font-family="sans-serif" font-weight="bold" fill="#282828"'
        ' text-anchor="middle">Sales by Region</text>' in s,
        "title centers on the legend-narrowed inner plot rect (137), not the full outer width (200)",
    )


def test_render_labels_default_matches_unlabeled_output_exactly() raises:
    # Plot.labels()'s defaults (all three strings "") must reproduce
    # the exact pre-existing no-labels render byte-for-byte -- the same
    # "purely additive" bar every optional feature added to this file
    # has had to clear (see e.g. Theme.line_smoothing's equivalent
    # test). Compared pixel-for-pixel across the whole canvas between a
    # plot that never calls .labels() at all and one that calls it with
    # every argument left at its default.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var _hoisted1 = Plot().mark_line().encode(x=x, y=y).size(400, 300)
    var c_unlabeled = render(_hoisted1)
    var _hoisted2 = Plot().mark_line().encode(x=x, y=y).labels().size(400, 300)
    var c_explicit = render(_hoisted2)

    for yy in range(c_unlabeled.height):
        for xx in range(c_unlabeled.width):
            var p_unlabeled = c_unlabeled.get_pixel(xx, yy)
            var p_explicit = c_explicit.get_pixel(xx, yy)
            assert_equal(p_unlabeled.r, p_explicit.r)
            assert_equal(p_unlabeled.g, p_explicit.g)
            assert_equal(p_unlabeled.b, p_explicit.b)


def test_render_title_draws_ink_in_its_own_reserved_top_band() raises:
    # A simpler, raster-side companion to the SVG string test above --
    # confirms canvas.text.draw_text actually got called with a
    # real, matching title (not just that the SVG backend's _TextRequest plumbing is correct): a fresh Canvas has no ink
    # anywhere at all before render(), so any non-background pixel
    # inside the reserved top band (y in [0, extra_top)) after
    # render() must be the title's ink.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var _hoisted3 = line(x, y, title="My Title", width=400, height=300)
    var c = render(_hoisted3)

    var found_ink = False
    for yy in range(22):  # extra_top, hand-derived above
        for xx in range(400):
            var p = c.get_pixel(xx, yy)
            if p.r != BG.r or p.g != BG.g or p.b != BG.b:
                found_ink = True
    assert_true(found_ink, "the title's ink, somewhere in its reserved top band")


def test_render_svg_subtitle_matches_hand_derived_position() raises:
    # Same setup as test_render_svg_labels_matches_hand_derived_title_
    # and_axis_titles above, plus a subtitle -- confirming subtitle's
    # reserved band shifts everything below it (the line mark itself
    # included) without disturbing title/x_title/y_title's positions.
    #
    # _apply_labels reserves extra_top=Int(18.0)+4 (title) +
    # Int(14.0)+4 (subtitle) = 22+18 = 40 (vs. 22 with no subtitle),
    # so the inner rect shrinks to (18, 40, 400, 282) -- shifting the
    # LINE mark's flat y=137.000 down to y=146.000 (the new
    # vertical midpoint: plot_y0=60, plot_y1=232). Title stays at its
    # unaffected (229, 14)
    # -- only its cross-axis position depends on the inner rect, and
    # that didn't change (still legend-less, same horizontal center).
    # Subtitle sits directly below it, at y=oy0+title_band+Int(14.0*
    # 0.8)=0+22+11=33, in Theme.subtitle_color's default muted
    # gray (#6e6e6e = Color(110,110,110)), normal weight (no font-
    # weight attribute).
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .labels(title="My Title", subtitle="A subtitle", x_title="X Axis", y_title="Y Axis")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true(
        '<text x="229" y="14" font-size="18.000" font-family="sans-serif" font-weight="bold" fill="#282828"'
        ' text-anchor="middle">My Title</text>' in s,
        "title -- unaffected by the subtitle's reserved band",
    )
    assert_true(
        '<text x="229" y="33" font-size="14.000" font-family="sans-serif" fill="#6e6e6e"'
        ' text-anchor="middle">A subtitle</text>' in s,
        "subtitle -- directly below the title, muted gray, normal weight",
    )
    assert_true(
        '<path d="M91.727,146.000 L366.273,146.000" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>' in s,
        "the LINE mark itself, shifted down by the subtitle's reserved band",
    )


def test_render_svg_subtitle_without_title_draws_at_the_top() raises:
    # Plot.labels()'s "each of the four is independent" rule --
    # a subtitle with no title still draws, at the same top position a
    # title alone would have used (y=Int(14.0*0.8)=11, not floating
    # below a nonexistent title's reserved band).
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var plot = Plot().mark_line().encode(x=x, y=y).labels(subtitle="Only a subtitle").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="220" y="11" font-size="14.000" font-family="sans-serif" fill="#6e6e6e"'
        ' text-anchor="middle">Only a subtitle</text>' in s,
        "a lone subtitle draws at the top, no title above it to make room for",
    )


def test_render_labels_subtitle_default_matches_unlabeled_output_exactly() raises:
    # subtitle's default ("", not set) must reproduce the exact
    # pre-existing title-only render byte-for-byte -- the same
    # "purely additive" bar test_render_labels_default_matches_
    # unlabeled_output_exactly already clears for labels() as a whole,
    # narrowed here to subtitle specifically (title/x_title/y_title
    # both set, subtitle left at its default either implicitly or
    # explicitly).
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var _hoisted4 = Plot().mark_line().encode(x=x, y=y).labels(title="T", x_title="X", y_title="Y").size(400, 300)
    var c_no_subtitle = render(_hoisted4)
    var _hoisted5 = Plot().mark_line().encode(x=x, y=y).labels(title="T", subtitle="", x_title="X", y_title="Y").size(400, 300)
    var c_explicit_empty = render(_hoisted5)

    for yy in range(c_no_subtitle.height):
        for xx in range(c_no_subtitle.width):
            var p1 = c_no_subtitle.get_pixel(xx, yy)
            var p2 = c_explicit_empty.get_pixel(xx, yy)
            assert_equal(p1.r, p2.r)
            assert_equal(p1.g, p2.g)
            assert_equal(p1.b, p2.b)


def test_render_labels_raises_x_title_or_y_title_on_arc() raises:
    # _apply_labels' explicit "no sensible axis to caption" check
    # -- Mark.ARC has no x/y axes at all (_render_arc's docstring),
    # so setting x_title/y_title on one raises rather than silently
    # dropping a caller's request, the same "raise on a setting
    # that can't apply" rule Plot.encode's color/size-on-a-non-
    # POINT-mark check follows. title alone (no axis titles)
    # is fine for Mark.ARC -- checked separately, not raised here.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted6 = pie(cats, vals, x_title="X", width=200, height=150)
        _ = render(_hoisted6)
    with assert_raises():
        var _hoisted7 = pie(cats, vals, y_title="Y", width=200, height=150)
        _ = render(_hoisted7)
    # title alone must NOT raise for Mark.ARC.
    var _hoisted8 = pie(cats, vals, title="Share", width=200, height=150)
    _ = render(_hoisted8)

# ---------------------------------------------------------------
# from tests/test_theme.mojo
# ---------------------------------------------------------------

def test_render_theme_scale_uniformly_scales_the_whole_layout() raises:
    # Theme.scale=2.0, paired with a canvas twice the width/height, is
    # meant to reproduce the exact same chart at twice the pixel
    # density -- so this reuses (not re-derives) test_render_point_
    # mark_centers_on_the_hand_derived_pixel's single-(5.0, 5.0)-
    # point setup, at 2x: canvas 800x600 (2x of 400x300), default
    # margins doubled by _Scaled (left=120, right=40, top=40,
    # bottom=100), giving a plot area of x:[120,760], y:[40,500] --
    # exactly 2x test_render_point_mark_centers_on_the_hand_derived_
    # pixel's x:[60,380], y:[20,250]. The point's pixel
    # (440, 270) is exactly double (220, 135) for the same reason:
    # LinearScale.to_pixel() of a domain's midpoint always lands
    # on the range's midpoint, and doubling a range's endpoints
    # doubles its midpoint too.
    var xy: List[Float64] = [5.0]
    var t = Theme(scale=2.0)
    var _hoisted1 = scatter(xy, xy, theme=t, width=800, height=600)
    var c = render(_hoisted1)

    _assert_color(c, 440, 270, t.mark_color, "scale=2.0's point, exactly 2x the scale=1.0 pixel")
    # The y-axis line itself, confirming the *margin* scaled (not just
    # incidentally landing on the right point pixel) -- plot_x0=120
    # spans the axis line from plot_y0=40 to plot_y1=500, and 270 is
    # well inside that span.
    _assert_color(c, 120, 270, t.axis_color, "scale=2.0's y-axis line, at the doubled margin")


def test_render_theme_scale_default_matches_unscaled_output_exactly() raises:
    # scale's default (1.0) must reproduce the exact pre-existing
    # unscaled render byte-for-byte -- not just "close", since every
    # pre-existing hand-derived pixel test in this file already
    # depends on that. Cross-checked directly here too: the identical
    # single-point setup, compared pixel-for-pixel between an explicit
    # Theme(scale=1.0) and Theme's bare default.
    var xy: List[Float64] = [5.0]
    var _hoisted2 = scatter(xy, xy, width=400, height=300)
    var c_default = render(_hoisted2)
    var _hoisted3 = scatter(xy, xy, theme=Theme(scale=1.0), width=400, height=300)
    var c_explicit = render(_hoisted3)

    for y in range(c_default.height):
        for x in range(c_default.width):
            var p_default = c_default.get_pixel(x, y)
            var p_explicit = c_explicit.get_pixel(x, y)
            assert_equal(p_default.r, p_explicit.r)
            assert_equal(p_default.g, p_explicit.g)
            assert_equal(p_default.b, p_explicit.b)


def test_render_theme_font_family_reaches_svg_output() raises:
    # A custom font_family ("Georgia") shows up as a literal
    # font-family="Georgia" attribute on every <text> element SVG
    # emits. Single point, canvas 400x300,
    # default theme otherwise: the same setup test_render_theme_scale_
    # uniformly_scales_the_whole_layout's 1x case reuses, so the
    # first tick label ("4.0" on the y-axis) lands at the same (60,
    # 271) that case's math establishes.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(font_family="Georgia")).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="60" y="271" font-size="12.000" font-family="Georgia" fill="#282828"'
        ' text-anchor="middle">4.0</text>' in s,
        "a y-axis tick label, carrying the custom font_family",
    )


def test_render_theme_font_family_default_matches_sans_serif_explicit() raises:
    # font_family's bare default ("sans-serif") must reproduce the
    # exact same output as passing that same value explicitly -- the
    # same explicit-default-value guarantee test_render_theme_scale_
    # default_matches_unscaled_output_exactly proves for scale,
    # exercised through the actual construction-time-baked-in code
    # path rather than just trusting the parameter's default.
    var xy: List[Float64] = [5.0]
    var _hoisted4 = scatter(xy, xy, width=400, height=300)
    var c_default = render(_hoisted4)
    var _hoisted5 = scatter(xy, xy, theme=Theme(font_family="sans-serif"), width=400, height=300)
    var c_explicit = render(_hoisted5)

    for y in range(c_default.height):
        for x in range(c_default.width):
            var p_default = c_default.get_pixel(x, y)
            var p_explicit = c_explicit.get_pixel(x, y)
            assert_equal(p_default.r, p_explicit.r)
            assert_equal(p_default.g, p_explicit.g)
            assert_equal(p_default.b, p_explicit.b)


def test_render_theme_font_family_actually_changes_raster_glyphs() raises:
    # A genuinely different family (monospace, vs. the default sans-
    # serif) must change the actual rendered raster glyphs, not just
    # the SVG markup -- proof `family` reaches canvas.text.
    # draw_text's raster path too, not only SvgCanvas.draw_text.
    # Sampling a small box around the first y-axis tick label ("4.0"
    # at pixel (60, 271), see the SVG test above) rather than a single
    # pixel: a font-shape difference shows up as *some* pixel in the
    # glyph's footprint changing, not necessarily every pixel or
    # any one specific one, so this counts differing pixels in a
    # small region around the label instead of asserting an exact
    # value -- a real, nonzero difference exists in that region.
    var xy: List[Float64] = [5.0]
    var _hoisted6 = scatter(xy, xy, theme=Theme(font_family="sans-serif"), width=400, height=300)
    var c_sans = render(_hoisted6)
    var _hoisted7 = scatter(xy, xy, theme=Theme(font_family="monospace"), width=400, height=300)
    var c_mono = render(_hoisted7)

    var diff_count = 0
    for y in range(260, 280):
        for x in range(45, 75):
            var p1 = c_sans.get_pixel(x, y)
            var p2 = c_mono.get_pixel(x, y)
            if p1.r != p2.r or p1.g != p2.g or p1.b != p2.b:
                diff_count += 1
    assert_true(diff_count > 0, "monospace vs sans-serif must render visibly different glyphs")


def test_render_theme_title_bold_default_emits_font_weight_bold() raises:
    # title_bold's default (True) emits a literal font-weight="bold"
    # attribute on the title's <text> element. Single point, canvas 400x300,
    # title "Hi" -- the same no-legend geometry test_render_theme_
    # scale_uniformly_scales_the_whole_layout's 1x case
    # establishes, so the title lands at the same (220, 14) that
    # case's math implies for this canvas size.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).labels(title="Hi").size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="220" y="14" font-size="18.000" font-family="sans-serif" font-weight="bold"'
        ' fill="#282828" text-anchor="middle">Hi</text>' in s,
        "the title, bold by default",
    )


def test_render_theme_title_bold_false_reproduces_the_old_no_bold_output() raises:
    # title_bold=False must reproduce the plain title output -- no
    # font-weight attribute at all, not font-weight="normal". Same
    # setup as the default-bold test above.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).labels(title="Hi").theme(Theme(title_bold=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="220" y="14" font-size="18.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">Hi</text>' in s,
        "the title, title_bold=False reproduces the old un-bolded output",
    )


def test_render_theme_title_bold_only_affects_the_title() raises:
    # Bold is scoped to the chart title alone -- x_title/y_title (and
    # every other _TextRequest) stay normal weight regardless of
    # title_bold, matching Theme.title_bold's docstring ("one
    # deliberate exception, not a general knob"): with both an x_title
    # and a title present, exactly one font-weight="bold" attribute
    # appears in the whole document.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).labels(title="Hi", x_title="X").size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    var count = 0
    var search_from = 0
    while True:
        var idx = s.find('font-weight="bold"', search_from)
        if idx == -1:
            break
        count += 1
        search_from = idx + 1
    assert_equal(count, 1, "exactly one bold text element -- the title, not x_title")


def test_theme_mark_style_fields_actually_change_output() raises:
    # A default-vs-overridden render must differ somewhere, or the
    # field is wired to nothing. A total row is required: the
    # narrow-delta width only applies when the chart actually has
    # totals to contrast against (see _render_waterfall -- with no
    # totals every bar spans its full band, and this fraction is
    # correctly ignored) -- without one, this test would pass even
    # against a field wired to nothing.
    var cats: List[String] = ["a", "b", "total"]
    var vals: List[Float64] = [3.0, -2.0, 1.0]
    var totals: List[Bool] = [False, False, True]

    var _hoisted8 = waterfall(cats, vals, totals, theme=Theme(), width=200, height=150)
    var base = render(_hoisted8)
    var _hoisted9 = waterfall(
        cats, vals, totals,
        delta_width_fraction=0.95, width=200, height=150,
    )
    var wide = render(_hoisted9)
    assert_true(
        _count_color(base, Theme().mark_color) != _count_color(wide, Theme().mark_color),
        "delta_width_fraction changes how much band a delta bar covers",
    )

    var measure: List[Float64] = [7.0]
    var target: List[Float64] = [8.0]
    var ranges: List[List[Float64]] = [[4.0, 6.0, 10.0]]
    var _hoisted10 = bullet(cats0(), measure, target, ranges, theme=Theme(), width=200, height=150)
    var b_thin = render(_hoisted10)
    var _hoisted11 = bullet(
        cats0(), measure, target, ranges,
        measure_width_fraction=0.9, width=200, height=150,
    )
    var b_fat = render(_hoisted11)
    assert_true(
        _count_color(b_thin, Theme().mark_color) != _count_color(b_fat, Theme().mark_color),
        "measure_width_fraction changes the measure bar's thickness",
    )


def cats0() -> List[String]:
    return ["only"]


def test_theme_mark_colors_are_actually_used() raises:
    # treemap_label_color and radialbar_track_color are pure color
    # swaps -- assert the overridden color appears at all, which the
    # default palette would never produce on its own.
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 5.0, 3.0]
    # Counted as "reddish" rather than exactly RED: quickplot renders
    # supersampled and downsamples, so an antialiased glyph keeps no
    # pixel at the pure source color. The label is unmistakably red
    # either way, which is what this asserts.
    var _hoisted12 = treemap(ids, parents, values, theme=Theme(treemap_label_color=RED), width=300, height=200)
    var t = render(_hoisted12)
    var reddish = 0
    for y in range(t.height):
        for x in range(t.width):
            var px = t.get_pixel(x, y)
            if px.r > 180 and px.g < 90 and px.b < 90:
                reddish += 1
    assert_true(reddish > 0, "treemap_label_color reaches the label")

    # Values must sit well below the maximum, or every ring sweeps a
    # full turn and there is no unfilled track left to color at all.
    var rb_cats: List[String] = ["x", "y"]
    var rb_vals: List[Float64] = [1.0, 8.0]
    var _hoisted13 = radialbar(
        rb_cats, rb_vals, theme=Theme(radialbar_track_color=RED), width=300, height=220
    )
    var r = render(_hoisted13)
    assert_true(_count_color(r, RED) > 0, "radialbar_track_color reaches the unfilled track")


def test_theme_layout_fields_reach_scaled() raises:
    # Layout fields differ from the mark-style fields above: these are
    # pixel quantities that must keep flowing through _Scaled, so a bare
    # "does the output change" check is not enough -- it must also
    # still multiply by Theme.scale for HiDPI.
    var t1 = Theme(tick_length=5)
    var t2 = Theme(tick_length=20)
    assert_equal(_Scaled(t1).tick_length, 5, "default tick_length reaches _Scaled")
    assert_equal(_Scaled(t2).tick_length, 20, "overridden tick_length reaches _Scaled")

    # .and still scales. 20 at scale 2.0 is 40, not 20.
    assert_equal(
        _Scaled(Theme(tick_length=20, scale=2.0)).tick_length, 40,
        "a themed tick_length is still multiplied by Theme.scale",
    )
    assert_equal(
        _Scaled(Theme(legend_width=200, scale=3.0)).legend_width, 600,
        "legend_width scales too",
    )

    # legend_swatch_size and continuous_legend_bar_width are
    # independent fields, not one defined in terms of the other --
    # changing the swatch must never silently move the gradient bar.
    var decoupled = _Scaled(Theme(legend_swatch_size=40))
    assert_equal(decoupled.legend_swatch_size, 40, "swatch size changed")
    assert_equal(
        decoupled.continuous_legend_bar_width, 14,
        "the gradient bar doesn't follow the swatch size",
    )


def test_theme_legend_width_actually_changes_layout() raises:
    # The end-to-end half: a wider legend column must take real space
    # away from the plot area, not just sit in _Scaled.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["alpha", "beta"]
    var _hoisted14 = Plot().mark_point().encode(x=x, y=y, color_categories=cats)
           .theme(Theme(legend_width=80, show_gridlines=False)).size(400, 300)
    var narrow = render(_hoisted14)
    var _hoisted15 = Plot().mark_point().encode(x=x, y=y, color_categories=cats)
           .theme(Theme(legend_width=260, show_gridlines=False)).size(400, 300)
    var wide = render(_hoisted15)
    assert_true(
        _count_color(narrow, BG) != _count_color(wide, BG),
        "legend_width changes how much canvas the plot area gets",
    )

# ---------------------------------------------------------------
# from tests/test_legends.mojo
# ---------------------------------------------------------------

def test_render_legend_swatches_match_hand_derived_positions_and_colors() raises:
    # Same setup as the categorical color test above (canvas 400x300,
    # default theme, plot area narrowed to x:[60,250] by the 130px
    # legend reserve). The legend column starts at x = plot_x1 +
    # margin_right = 250+20 = 270, y = plot_y0 = 20. Row 0 ("A")'s
    # 14x14 swatch sits at (270,20); row 1 ("B")'s at (270, 20 +
    # (14+8)) = (270,42) -- both solved directly from _draw_legend's
    # layout constants, not read off the code's output. Checked at
    # each swatch's center (270+7, row_y+7) so a boundary/rounding
    # difference of a pixel or two wouldn't produce a false failure.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats).size(400, 300)
    var c = render(plot)

    var palette = default_categorical_palette()
    _assert_color(c, 277, 27, palette[0], "legend row 0 swatch -- category A")
    _assert_color(c, 277, 49, palette[1], "legend row 1 swatch -- category B")


def test_render_legend_disabled_restores_the_full_plot_width() raises:
    # theme.show_legend=False -- confirms legend_reserve actually goes
    # back to 0, not just that no legend pixels are drawn: the point
    # positions themselves must return to exactly the same pixel
    # centers (75,135)/(365,135) the *continuous* color test (with no
    # legend at all) uses, since the plot area regains its full
    # original width x:[60,380].
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var t = Theme(show_legend=False)
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats).theme(t).size(400, 300)
    var c = render(plot)

    var palette = default_categorical_palette()
    _assert_color(c, 75, 135, palette[0], "category A, full-width layout")
    _assert_color(c, 365, 135, palette[1], "category B, full-width layout")
    # Where the legend *would* have been drawn is plain background now.
    _assert_color(c, 277, 27, BG, "no legend drawn when show_legend=False")


def test_render_svg_continuous_color_legend_matches_hand_derived_gradient() raises:
    # x=[0,10], y=[0,10], color=[0.0,10.0] (continuous, no size) --
    # canvas 400x300, default theme, show_gridlines=False. "10.0"/"0.0"
    # (26.0px/19.0px at the default 12pt font) both stay well under
    # the 130px default legend width, so
    # legend_reserve stays at that default, unchanged -- plot_x1=
    # 400-20-130=250, legend anchor (x=270, y=20), bar 14 wide, 100
    # tall (x:[270,284], y:[20,120]).
    #
    # A real DrawTarget.fill_rect_gradient bar, built from
    # ColorScale's three stops (ColorScale.from_theme: color_scale_
    # low/mid/high at 0.0/0.5/1.0, see that method's docstring for why
    # a middle stop exists at all -- Theme.color_scale_mid's docstring
    # has the real, rendering-caught readability bug it fixes), each
    # one's gradient offset flipped (1.0 - stop.offset, see _draw_
    # continuous_color_legend's docstring for why: the bar's top has to
    # be the *high* value, but ColorScale's offset 1.0 already means
    # high).
    #
    # The flip reverses their order, so they are sorted back into
    # ASCENDING offset order before being emitted: offset 0.0 =
    # color_scale_high (#dc5a28, Color(220,90,40)) at the bar's top,
    # offset 0.5 = color_scale_mid (#ebebeb, Color(235,235,235)), and
    # offset 1.0 = color_scale_low (#3c6ec8, Color(60,110,200)) at its
    # bottom. That ordering matters: SVG clamps every <stop> offset to
    # be no less than the previous one's, so a descending list would
    # collapse onto one offset and render as a single flat color in
    # any real SVG viewer, even though the raster backend (_color_at_t
    # scans for the bracketing pair rather than assuming sorted input)
    # would render the identical gradient correctly.
    #
    # An assertion written by reading rendered output back can confirm
    # the markup matches what the code produces, but never that the
    # markup is *valid SVG* -- it cannot catch a bug that lives in the
    # output itself. Hence the explicit ascending-order check below,
    # which is about the format's requirement rather than about this
    # particular render.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var color: List[Float64] = [0.0, 10.0]
    var plot = Plot().mark_point().encode(x=x, y=y, color=color).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true(
        '<linearGradient id="grad1" gradientUnits="userSpaceOnUse" x1="270.000" y1="20.000"'
        ' x2="270.000" y2="120.000"><stop offset="0.000" stop-color="#dc5a28" stop-opacity="1.000"/>'
        '<stop offset="0.500" stop-color="#ebebeb" stop-opacity="1.000"/>'
        '<stop offset="1.000" stop-color="#3c6ec8" stop-opacity="1.000"/></linearGradient>' in s,
        "the gradient definition: high color at the top (offset 0.0), mid at the middle (offset"
        " 0.5), low color at the bottom (offset 1.0) -- in ascending offset order, as SVG requires",
    )
    # The ordering requirement on its own, independent of these three
    # particular colors: a future change to the palette or to the stop
    # count must not be able to reintroduce descending offsets.
    var at_0 = s.find('offset="0.000"')
    var at_half = s.find('offset="0.500"')
    var at_1 = s.find('offset="1.000"')
    assert_true(at_0 >= 0 and at_half >= 0 and at_1 >= 0, "all three stops reach the SVG")
    assert_true(
        at_0 < at_half and at_half < at_1,
        "SVG gradient stop offsets must be emitted in ascending order -- SVG clamps each one to be"
        " no less than the previous, so a descending list collapses the whole gradient into a"
        " single flat color",
    )
    assert_true(
        '<rect x="270" y="20" width="14" height="100" fill="url(#grad1)"/>' in s,
        "the gradient bar itself, filled by reference to that gradient",
    )
    assert_true(
        '<text x="288" y="24" font-size="12.000" font-family="sans-serif" fill="#282828" text-anchor="start">10.0</text>' in s,
        "domain max label, at the bar's top",
    )
    assert_true(
        '<text x="288" y="124" font-size="12.000" font-family="sans-serif" fill="#282828" text-anchor="start">0.0</text>' in s,
        "domain min label, at the bar's bottom",
    )


def test_render_svg_continuous_size_legend_matches_hand_derived_circles() raises:
    # x=[0,10], y=[0,10], size=[2.0,8.0] (continuous, no color) --
    # same plot_x1=250, legend anchor (270,20) as the color-legend test
    # above (size_range_min/max default to 3.0/15.0, and this data's
    # three representative labels -- "8.0"/"5.0"/"2.0", all 19.0px
    # -- also stay under the 130px default). Three circles at max
    # (8.0 -> radius 15), midpoint (5.0 -> radius 9), and min (2.0 ->
    # radius 3) of the *data's* size domain, left-aligned on
    # Theme's configured largest radius (cx = 270 + 15 = 285) so
    # every label lines up regardless of which circle is biggest.
    # Every center/radius/label position independently re-derived via
    # python3 (LinearScale's slope/intercept for the size scale).
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var size: List[Float64] = [2.0, 8.0]
    var plot = Plot().mark_point().encode(x=x, y=y, size=size).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true('<circle cx="285" cy="35" r="15" fill="#1e64b4"/>' in s, "max (8.0) -> radius 15")
    assert_true('<circle cx="285" cy="67" r="9" fill="#1e64b4"/>' in s, "midpoint (5.0) -> radius 9")
    assert_true('<circle cx="285" cy="87" r="3" fill="#1e64b4"/>' in s, "min (2.0) -> radius 3")
    assert_true(
        '<text x="304" y="39" font-size="12.000" font-family="sans-serif" fill="#282828" text-anchor="start">8.0</text>' in s,
        "max circle's label",
    )
    assert_true(
        '<text x="298" y="71" font-size="12.000" font-family="sans-serif" fill="#282828" text-anchor="start">5.0</text>' in s,
        "midpoint circle's label",
    )
    assert_true(
        '<text x="292" y="91" font-size="12.000" font-family="sans-serif" fill="#282828" text-anchor="start">2.0</text>' in s,
        "min circle's label",
    )


def test_render_point_continuous_legends_are_off_by_default_theme_setting() raises:
    # Theme(show_legend=False) suppresses continuous color/size legends
    # the same way it already suppresses the categorical one -- the
    # plot area regains its full original width.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var color: List[Float64] = [0.0, 10.0]
    var t = Theme(show_legend=False)
    var plot = Plot().mark_point().encode(x=x, y=y, color=color).theme(t).size(400, 300)
    var c = render(plot)
    _assert_color(c, 365, 135, t.color_scale_high, "point regains the full-width layout's pixel center")
    _assert_color(c, 277, 27, BG, "no continuous color legend drawn when show_legend=False")


def test_render_point_legend_width_grows_to_fit_long_category_names() raises:
    # "Southeast Region Sales" measures 140.4px at the default 12pt
    # font, against this environment's real "Sans" font metrics
    # (unhinted, so glyph widths depend on the installed font file).
    # _dynamic_legend_width = max(130, 14+4+140+8) =
    # max(130, 166) = 166, wider than Theme's default 130px legend
    # column -- so plot_x1 becomes 400-20-166=214, not 400-20-130=250.
    # Legend swatch row 0 at x=plot_x1+margin_right=214+20=234, y=
    # plot_y0=20.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["Cat1", "Southeast Region Sales"]
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="234" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "legend column shifted left to make room for the long label",
    )
    assert_true(
        '<rect x="234" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "the long label's legend swatch",
    )


def test_render_grouped_bar_legend_width_grows_to_fit_long_series_names() raises:
    # Same 140.4px-wide "Southeast Region Sales" label, same math as
    # the Mark.POINT test just above -- dynamic_legend_width=166,
    # plot_x1=400-166-20=214, legend swatch row 0 at x=214+20=234.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "Southeast Region Sales"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="234" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "North's legend swatch, shifted left to make room for the wider label",
    )
    assert_true(
        '<rect x="234" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "the long label's legend swatch",
    )

# ---------------------------------------------------------------
# from tests/test_marker.mojo
# ---------------------------------------------------------------

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

# ---------------------------------------------------------------
# from tests/test_svg_accessibility.mojo
# ---------------------------------------------------------------

def test_accessible_svg_string_adds_role_and_aria_label_to_root_element() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    var svg = render_svg(plot)
    var s = accessible_svg_string(svg, "Widget Sales")
    assert_true(
        '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300" viewBox="0 0 400 300"'
        ' role="img" aria-label="Widget Sales">' in s,
        "the root element gains role=\"img\" and aria-label, its original attributes untouched",
    )


def test_accessible_svg_string_adds_title_and_desc_as_leading_children() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    var svg = render_svg(plot)
    var s = accessible_svg_string(svg, "Widget Sales", "A bar chart of widget sales by category.")
    var title_idx = s.find("<title>Widget Sales</title>")
    var desc_idx = s.find("<desc>A bar chart of widget sales by category.</desc>")
    var first_rect_idx = s.find("<rect")
    assert_true(title_idx != -1, "the <title> element is present")
    assert_true(desc_idx != -1, "the <desc> element is present")
    assert_true(
        title_idx < desc_idx < first_rect_idx,
        "both come before the chart's first drawn element, not scattered elsewhere",
    )


def test_accessible_svg_string_omits_desc_when_description_is_empty() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    var svg = render_svg(plot)
    var s = accessible_svg_string(svg, "Widget Sales")
    assert_true("<desc>" not in s, "no description was given, so no <desc> element draws at all")


def test_accessible_svg_string_escapes_special_characters() raises:
    # Both the attribute (aria-label) and text-content (<title>)
    # contexts have different escaping rules -- '"' must escape inside
    # a double-quoted attribute but not inside element text.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    var svg = render_svg(plot)
    var s = accessible_svg_string(svg, 'Sales & "Returns" <2024>')
    assert_true(
        'aria-label="Sales &amp; &quot;Returns&quot; &lt;2024>"' in s,
        "the attribute value escapes &, \", and < (the delimiter itself never needs escaping)",
    )
    assert_true(
        '<title>Sales &amp; "Returns" &lt;2024&gt;</title>' in s,
        "the element text escapes &, <, and > but not \" (a different context, different rules)",
    )


def test_accessible_svg_string_preserves_the_chart_body_unchanged() raises:
    # The actual chart markup underneath the new accessibility wrapper
    # must be byte-for-byte what render_svg() itself produced -- this
    # function only ever adds markup around it, never touches it.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    var svg = render_svg(plot)
    var original = svg.to_string()
    var accessible = accessible_svg_string(svg, "Widget Sales")
    # Every line of the original body (everything after its first
    # ">") still appears, unmodified, inside the accessible version.
    var body_start = original.find(">") + 1
    var body = String(original[byte=body_start:])
    assert_true(body in accessible, "the original chart body survives completely unchanged")


def test_svg_tooltips_wrap_each_datum_in_a_titled_group() raises:
    """Each bar gets a `<g><title>` a browser shows on hover, with the
    title XML-escaped by canvas_mojo (so a category containing `&` or
    `<` is safe to pass through raw) and the value formatted the same
    way `Theme.show_data_labels` formats it."""
    var cats: List[String] = ["A & B", "C<D>", "E"]
    var vals: List[Float64] = [10.0, -5.5, 20.25]
    var svg = render_svg(bar(cats, vals, width=300, height=200)).to_string()

    assert_true("<title>A &amp; B: 10</title>" in svg, "ampersand escaped, value formatted")
    assert_true("<title>C&lt;D&gt;: -5.5</title>" in svg, "angle brackets escaped, negative value")
    assert_true("<title>E: 20.25</title>" in svg, "decimals kept only where they matter")
    # One group per bar, each closed.
    assert_equal(svg.count("<g>"), 3, "one group per bar")
    assert_equal(svg.count("</g>"), 3, "every group closed")


def test_svg_tooltips_off_emits_no_groups_at_all() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var svg = render_svg(
        bar(cats, vals, theme=Theme(svg_tooltips=False), width=200, height=150)
    ).to_string()
    assert_true("<g>" not in svg, "no groups when tooltips are off")
    assert_true("<title>" not in svg, "no titles when tooltips are off")


def test_svg_tooltips_leave_the_raster_backend_byte_identical() raises:
    """`Canvas` no-ops both group calls, so a raster render is
    unaffected by the flag -- the asymmetry is the point, since a
    bitmap has nowhere to put a title."""
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var on = bar(cats, vals, theme=Theme(svg_tooltips=True), width=200, height=150)
    var off = bar(cats, vals, theme=Theme(svg_tooltips=False), width=200, height=150)
    var c_on = render(on)
    var c_off = render(off)
    assert_equal(c_on.width, c_off.width, "same width")
    assert_equal(c_on.height, c_off.height, "same height")
    for y in range(c_on.height):
        for x in range(c_on.width):
            var a = c_on.get_pixel(x, y)
            var b = c_off.get_pixel(x, y)
            if a.r != b.r or a.g != b.g or a.b != b.b:
                assert_true(False, "raster differs at " + String(x) + "," + String(y))


def test_svg_tooltips_are_purely_additive_markup() raises:
    """Turning tooltips on adds `<g>`/`<title>`/`</g>` lines and
    changes nothing else -- the property that makes this safe to
    default on. Strip those lines back out and the two documents are
    identical."""
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [4.0, 9.0]
    var on = render_svg(bar(cats, vals, width=200, height=150)).to_string()
    var off = render_svg(
        bar(cats, vals, theme=Theme(svg_tooltips=False), width=200, height=150)
    ).to_string()

    var stripped = String("")
    var first = True
    for line in on.split("\n"):
        var t = String(line).strip()
        if t == "<g>" or t == "</g>" or (t.startswith("<title>") and t.endswith("</title>")):
            continue
        if not first:
            stripped += "\n"
        stripped += line
        first = False
    assert_equal(stripped, off, "tooltip markup is additive; nothing else moves")


def test_svg_tooltip_for_a_box_is_its_five_number_summary() raises:
    """A box plot's group covers all five primitives (box, whiskers,
    caps, median) as one datum, and says what the shape encodes.
    Outliers sit outside that group with their own title, since each is
    its own datum rather than part of the summary."""
    var cats: List[String] = ["Group A"]
    var vals: List[List[Float64]] = [[20.0, 55.0, 70.0, 75.0, 80.0, 82.0, 140.0]]
    var svg = render_svg(box(cats, vals, width=300, height=200)).to_string()

    assert_true("median 75" in svg, "median in the summary")
    assert_true("Q1 62.5" in svg, "first quartile in the summary")
    assert_true("range 55-82" in svg, "whisker range in the summary")
    assert_true("<title>Group A: 20 (outlier)</title>" in svg, "low outlier titled separately")
    assert_true("<title>Group A: 140 (outlier)</title>" in svg, "high outlier titled separately")


def test_point_tooltips_are_off_by_default_and_opt_in_per_chart() raises:
    """Unlike the categorical marks, a scatter's tooltips are off until
    the chart asks for them -- a title costs about as much as the
    `<circle>` it annotates, so turning them on roughly doubles a dense
    scatter's SVG."""
    var xs: List[Float64] = [1.0, 2.5, 3.0]
    var ys: List[Float64] = [10.0, 20.5, 30.0]

    var off = render_svg(scatter(xs, ys, width=250, height=180)).to_string()
    assert_equal(off.count("<title>"), 0, "no titles by default")

    var on = render_svg(scatter(xs, ys, tooltips=True, width=250, height=180)).to_string()
    assert_true("<title>1, 10</title>" in on, "coordinates, formatted like every other label")
    assert_true("<title>2.5, 20.5</title>" in on, "decimals kept only where they matter")
    assert_equal(on.count("<title>"), 3, "one per point")


def test_point_tooltip_prefers_the_row_s_own_label_over_coordinates() raises:
    """`encode(labels=...)` text was chosen by the caller to identify
    the point, so it beats anything derived -- but a row left empty
    still gets coordinates rather than a blank tooltip."""
    var xs: List[Float64] = [1.0, 2.5, 3.0]
    var ys: List[Float64] = [10.0, 20.5, 30.0]
    var labs: List[String] = ["alpha", "", "gamma"]
    var plot = Plot().mark_point(tooltips=True).encode(x=xs, y=ys, labels=labs).size(250, 180)
    var svg = render_svg(plot).to_string()

    assert_true("<title>alpha</title>" in svg, "caller's label wins")
    assert_true("<title>gamma</title>" in svg, "caller's label wins")
    assert_true("<title>2.5, 20.5</title>" in svg, "empty label falls back to coordinates")


def test_theme_svg_tooltips_off_overrides_the_per_chart_opt_in() raises:
    """The two controls are ANDed: Theme.svg_tooltips turns tooltips
    off globally, mark_point(tooltips=) turns them on for a chart that
    can afford them. Asking for both is what emits a title."""
    var xs: List[Float64] = [1.0, 2.0]
    var ys: List[Float64] = [3.0, 4.0]
    var svg = render_svg(
        scatter(xs, ys, tooltips=True, theme=Theme(svg_tooltips=False), width=200, height=150)
    ).to_string()
    assert_equal(svg.count("<title>"), 0, "theme off beats the chart's opt-in")


def test_beeswarm_tooltips_name_the_category_and_value() raises:
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0]]
    var off = render_svg(beeswarm(cats, vals, width=250, height=180)).to_string()
    assert_equal(off.count("<title>"), 0, "off by default, same as scatter")

    var on = render_svg(beeswarm(cats, vals, tooltips=True, width=250, height=180)).to_string()
    assert_true("<title>A: 1</title>" in on, "category and value")
    assert_true("<title>A: 2</title>" in on, "one per point, not per category")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
