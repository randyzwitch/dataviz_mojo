"""Tests for Plot.labels(): title/axis-title rendering and positioning
(raster + SVG), including precise centering on the legend-narrowed inner
plot rect -- split out of what used to be one big test_plot.mojo.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
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

from _test_helpers import BG, _count_color, _assert_color


def test_render_svg_labels_matches_hand_derived_title_and_axis_titles() raises:
    # Same x=[0,10]/y=[5,5] data as the plain-LINE SVG test just above,
    # now with all three of Plot.labels()'s own strings set -- default
    # Theme (title_font_size=18.0, axis_title_font_size=14.0,
    # label_gap=4), canvas 400x300, show_gridlines=False.
    #
    # _apply_labels reserves extra_top=Int(18.0)+4=22, extra_bottom=
    # Int(14.0)+4=18, extra_left=Int(14.0)+4=18 from the *outer* 400x300
    # bounds before _render_generic ever runs, so the inner rect handed
    # to it is (18, 22, 400, 282), not (0, 0, 400, 300) -- shifting
    # every plot-area/tick/line-endpoint coordinate the original LINE
    # SVG test hand-solved for the unshrunk canvas. Every position below
    # (titles' own anchors, and the line's own re-solved endpoints)
    # independently re-derived via python3 from that shrunk rect, then
    # confirmed against a real render_svg() run before trusting it here
    # -- the same cross-check discipline every hand-derived test in this
    # file follows, doubly so here since this is the first test to
    # exercise _apply_labels' own shrunk-rect math at all.
    #
    # Title/x_title/y_title all center on the *inner* plot rect
    # (_RenderResult's own px0/py0/px1/py1 -- see dataviz_mojo/ROADMAP.md's
    # own "Plot.labels() precise centering" Done entry), not the full
    # outer bounds -- confirmed here via the LINE mark's own already-
    # hand-solved endpoints just below: plot_x0=78 (frame.ox0=18 +
    # margin_left=60, no dynamic left-margin growth -- short y=5 tick
    # labels), plot_x1=380 (frame.ox1=400 - margin_right=20, no legend
    # on Mark.LINE), matching the line path's own re-solved
    # to_pixel(0)=91.727/to_pixel(10)=366.273 (slope solved from those
    # two points) below. plot_y0=42 (frame.oy0=22 + margin_top=20),
    # plot_y1=232 (frame.oy1=282 - margin_bottom=50) -- matching the
    # line's own flat y=137.000 (the exact vertical midpoint, y=[5,5]
    # constant data).
    #
    # Title: center=((78+380)//2, 14)=(229,14) -- horizontal center is
    # the inner rect's, but the *vertical* position (14) still comes
    # from the *original* outer oy0=0 (Int(18.0*0.8)=14), unaffected --
    # only the cross-axis coordinate moved, not the along-axis one (see
    # _label_text_requests' own docstring). No rotation (0.0, so no
    # transform attr).
    # x_title: center=(229,297) -- same horizontal center as title,
    # vertical position still from the original outer oy1=300
    # (300-Int(14.0*0.25)=297), unaffected.
    # y_title: (11,(42+232)//2)=(11,137) -- horizontal position still
    # from the original outer ox0=0 (Int(14.0*0.8)=11), unaffected; the
    # *vertical* center is now the inner rect's own (137, not the old
    # 150=outer-bounds-based value) -- rotation=-pi/2 -> exactly -90.000
    # degrees, confirmed correct (bottom-to-top reading, the standard
    # y-axis-title convention) via a real rendered raster probe before
    # trusting the sign in this SVG assertion.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var svg = SvgCanvas(400, 300)
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .labels(title="My Title", x_title="X Axis", y_title="Y Axis")
        .theme(Theme(show_gridlines=False))
    )
    render_svg(svg, plot)
    var s = svg.to_string()

    assert_true(
        '<text x="229" y="14" font-size="18.000" fill="#282828"'
        ' text-anchor="middle">My Title</text>' in s,
        "chart title -- centered over the inner plot rect, no rotation",
    )
    assert_true(
        '<text x="229" y="297" font-size="14.000" fill="#282828"'
        ' text-anchor="middle">X Axis</text>' in s,
        "x_title -- centered over the inner plot rect, near the bottom edge",
    )
    assert_true(
        '<text x="11" y="137" font-size="14.000" fill="#282828"'
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
    # Direct regression test for the "Plot.labels() precise centering"
    # fix: same long-category-name legend setup as test_render_point_
    # legend_width_grows_to_fit_long_category_names above (_dynamic_
    # legend_width=166, plot_x1=400-20-166=214; plot_x0 stays the
    # default margin_left=60 -- y=[0.0,0.0] pads to a short-labeled
    # domain, no dynamic-left-margin growth here), now with a chart
    # title too. Before this fix, the title centered on the full outer
    # canvas width ((0+400)//2=200, what test_render_svg_labels_matches_
    # hand_derived_title_and_axis_titles's own "My Title" case would
    # have used pre-fix); after it, the title centers on the *inner*
    # plot rect instead -- (60+214)//2=137 -- correctly shifted left of
    # the legend-narrowed data area's own true center, not the
    # legend-oblivious canvas center.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["Cat1", "Southeast Region Sales"]
    var svg = SvgCanvas(400, 300)
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cats)
        .labels(title="Sales by Region")
        .theme(Theme(show_gridlines=False))
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<text x="137" y="14" font-size="18.000" fill="#282828"'
        ' text-anchor="middle">Sales by Region</text>' in s,
        "title centers on the legend-narrowed inner plot rect (137), not the full outer width (200)",
    )


def test_render_labels_default_matches_unlabeled_output_exactly() raises:
    # Plot.labels()'s own defaults (all three strings "") must reproduce
    # the exact pre-existing no-labels render byte-for-byte -- the same
    # "purely additive" bar every optional feature added to this file
    # has had to clear (see e.g. Theme.line_smoothing's own equivalent
    # test). Compared pixel-for-pixel across the whole canvas between a
    # plot that never calls .labels() at all and one that calls it with
    # every argument left at its own default.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var c_unlabeled = Canvas(400, 300, BG)
    render(c_unlabeled, Plot().mark_line().encode(x=x, y=y))
    var c_explicit = Canvas(400, 300, BG)
    render(c_explicit, Plot().mark_line().encode(x=x, y=y).labels())

    for yy in range(c_unlabeled.height):
        for xx in range(c_unlabeled.width):
            var p_unlabeled = c_unlabeled.get_pixel(xx, yy)
            var p_explicit = c_explicit.get_pixel(xx, yy)
            assert_equal(p_unlabeled.r, p_explicit.r)
            assert_equal(p_unlabeled.g, p_explicit.g)
            assert_equal(p_unlabeled.b, p_explicit.b)


def test_render_title_draws_ink_in_its_own_reserved_top_band() raises:
    # A simpler, raster-side companion to the SVG string test above --
    # confirms canvas_mojo.text.draw_text actually got called with a
    # real, matching title (not just that the SVG backend's own
    # _TextRequest plumbing is correct): a fresh Canvas has no ink
    # anywhere at all before render(), so any non-background pixel
    # inside the reserved top band (y in [0, extra_top)) after
    # render() must be the title's own ink.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var c = Canvas(400, 300, BG)
    render(c, Plot().mark_line().encode(x=x, y=y).labels(title="My Title"))

    var found_ink = False
    for yy in range(22):  # extra_top, hand-derived above
        for xx in range(400):
            var p = c.get_pixel(xx, yy)
            if p.r != BG.r or p.g != BG.g or p.b != BG.b:
                found_ink = True
    assert_true(found_ink, "the title's own ink, somewhere in its reserved top band")


def test_render_labels_raises_x_title_or_y_title_on_arc() raises:
    # _apply_labels' own explicit "no sensible axis to caption" check
    # -- Mark.ARC has no x/y axes at all (_render_arc's own docstring),
    # so setting x_title/y_title on one raises rather than silently
    # dropping a caller's own request, the same "raise on a setting
    # that can't apply" rule Plot.encode's own color/size-on-a-non-
    # POINT-mark check already follows. title alone (no axis titles)
    # is fine for Mark.ARC -- checked separately, not raised here.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, Plot().mark_arc().encode_categorical(x=cats, y=vals).labels(x_title="X"))
    with assert_raises():
        render(c, Plot().mark_arc().encode_categorical(x=cats, y=vals).labels(y_title="Y"))
    # title alone must NOT raise for Mark.ARC.
    render(c, Plot().mark_arc().encode_categorical(x=cats, y=vals).labels(title="Share"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
