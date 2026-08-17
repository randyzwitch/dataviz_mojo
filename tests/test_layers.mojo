"""Tests for render_layers/render_layers_svg: shared-domain layering of
Mark.POINT/LINE/AREA, per-layer color/size encoding and legends, and the
raises-guards for every mark type layering doesn't support -- split out
of what used to be one big test_plot.mojo.
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


def test_render_layers_shares_one_domain_across_a_line_and_a_point() raises:
    # A LINE plot (x=[0,10], y=[0,10], default theme) layered with a
    # POINT plot (a single (5,5) point, custom red color + radius 5)
    # -- every coordinate below confirmed via a real render_layers()
    # run first (the same cross-check discipline every raw-float
    # assertion in this file uses), not derived from a hand-rolled
    # formula alone: the combined domain (both plots' x/y data
    # together) pads to [-0.5, 10.5] on both axes, landing the shared
    # point (5,5) -- coincidentally, since 5.0 is that domain's own
    # midpoint -- on the same (220, 135) pixel many other single-plot
    # tests in this file already use, and the line's own two endpoints
    # at (74.545, 239.545) and (365.455, 30.455).
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var point_x: List[Float64] = [5.0]
    var point_y: List[Float64] = [5.0]
    var plot_a = Plot().mark_line().encode(x=line_x, y=line_y).theme(Theme(show_gridlines=False))
    var plot_b = Plot().mark_point().encode(x=point_x, y=point_y).theme(
        Theme(mark_color=Color(255, 0, 0), point_radius=5.0)
    )
    var plots = List[Plot]()
    plots.append(plot_a^)
    plots.append(plot_b^)

    var c = Canvas(400, 300, BG)
    render_layers(c, plots)
    _assert_color(c, 220, 135, Color(255, 0, 0), "the layered point, at the shared domain's own pixel")

    var svg = SvgCanvas(400, 300)
    var svg_plots = List[Plot]()
    svg_plots.append(Plot().mark_line().encode(x=line_x, y=line_y).theme(Theme(show_gridlines=False)))
    svg_plots.append(
        Plot().mark_point().encode(x=point_x, y=point_y).theme(
            Theme(mark_color=Color(255, 0, 0), point_radius=5.0)
        )
    )
    render_layers_svg(svg, svg_plots)
    var s = svg.to_string()
    assert_true(
        '<path d="M74.545,239.545 L365.455,30.455" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the layered line, endpoints confirmed via a real render_layers_svg() run",
    )
    assert_true('<circle cx="220" cy="135" r="5" fill="#ff0000"/>' in s, "the layered point, same shared domain")


def test_render_layers_svg_title_from_plots0_centers_on_shared_inner_rect() raises:
    # Same LINE+POINT layered setup as the test just above, now with
    # plots[0] (the LINE plot) setting a chart title via .labels() --
    # confirming render_layers()'s own Plot.labels() support
    # (the wiki's Changelog, its own "Plot.labels() reaches
    # render_facets/render_layers" entry): the title comes from
    # plots[0] only (the same "shared chrome from plots[0]" convention
    # Theme already follows here -- see render_layers()'s own
    # docstring), and its own extra_top=Int(18.0)+4=22 reservation
    # shifts the *shared* plot_y0 from 20 to 42 -- affecting every
    # layer's own geometry together, not just plots[0]'s own, since
    # every layer draws into the identical shared inner rect (the
    # point's own cy moves from 135 to 146; the line's own endpoints
    # re-solved below via the same to_pixel formula the un-titled test
    # above already confirmed, just against range_max=42 instead of 20).
    # Title itself centers at ((60+380)//2, Int(18.0*0.8))=(220,14).
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var point_x: List[Float64] = [5.0]
    var point_y: List[Float64] = [5.0]
    var svg = SvgCanvas(400, 300)
    var plots = List[Plot]()
    plots.append(
        Plot().mark_line().encode(x=line_x, y=line_y).labels(title="Combined").theme(
            Theme(show_gridlines=False)
        )
    )
    plots.append(
        Plot().mark_point().encode(x=point_x, y=point_y).theme(
            Theme(mark_color=Color(255, 0, 0), point_radius=5.0)
        )
    )
    render_layers_svg(svg, plots)
    var s = svg.to_string()

    assert_true(
        '<text x="220" y="14" font-size="18.000" fill="#282828"'
        ' text-anchor="middle">Combined</text>' in s,
        "layered chart title, from plots[0], centered on the shared inner rect",
    )
    assert_true(
        '<path d="M74.545,240.545 L365.455,51.455" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the layered line, re-solved against the title-shrunk shared inner rect",
    )
    assert_true(
        '<circle cx="220" cy="146" r="5" fill="#ff0000"/>' in s,
        "the layered point, same shared domain, shifted down by the shared title reservation",
    )


def test_render_layers_svg_point_layer_color_categories_matches_hand_derived_legend() raises:
    # A single Mark.POINT layer (no other layers) with color_categories
    # encoding -- confirming render_layers()'s own per-point encoding +
    # legend support (the wiki's Changelog, its own "render_layers
    # per-point encoding and legends" entry). x=[0,10], y=[0.0,0.0]
    # (constant -- zero-span domain, padded to [-1,1], the same pattern
    # test_render_color_encoding_matches_hand_derived_colors above
    # already establishes), color_categories=["A","B"] -- short labels,
    # so the default 130px Theme.legend_width governs (not grown), and
    # plot_x1 becomes 400-20-130=250 (not 380, the no-legend value other
    # single-layer tests in this file use).
    #
    # x-domain pads [0,10] to [-0.5,10.5]; with plot_x0=60 (unaffected,
    # no dynamic left-margin growth -- short y=[-1,1] tick labels) and
    # this narrowed plot_x1=250, to_pixel(0)=68.636->69,
    # to_pixel(10)=241.364->241 (re-solved via the same LinearScale
    # slope/intercept formula every hand-derived pixel test in this file
    # uses, cross-checked in Python, not read off the code's own
    # output). y=[−1,1] domain's own midpoint (value 0.0) lands at the
    # exact vertical center of [plot_y0=20, plot_y1=250] -> 135, for
    # both points (constant y). Point 0 ("A") gets the default palette's
    # own first color (#1f77b4), point 1 ("B") the second (#ff7f0e) --
    # the identical two colors/ordering the single-plot categorical-
    # color tests in this file already confirm, reused unchanged since
    # render_layers's own per-layer encoding is exactly Mark.POINT's own
    # single-plot logic, not a reimplementation.
    #
    # Legend column at legend_x=plot_x1+margin_right=250+20=270, row 0
    # (swatch "A") at y=plot_y0=20, row 1 ("B") at y=20+(14+8)=42 -- the
    # identical swatch_size=14/row_gap=8 spacing test_render_point_
    # legend_width_grows_to_fit_long_category_names above already
    # establishes.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var svg = SvgCanvas(400, 300)
    var plots = List[Plot]()
    plots.append(
        Plot().mark_point().encode(x=x, y=y, color_categories=cats).theme(Theme(show_gridlines=False))
    )
    render_layers_svg(svg, plots)
    var s = svg.to_string()

    assert_true('<circle cx="69" cy="135" r="4" fill="#1f77b4"/>' in s, "layered point 0, category A's own color")
    assert_true('<circle cx="241" cy="135" r="4" fill="#ff7f0e"/>' in s, "layered point 1, category B's own color")
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "legend row 0 -- narrowed plot area makes room for the legend column",
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "legend row 1",
    )


def test_render_layers_raises_when_a_line_layer_uses_color_categories() raises:
    # The identical "only Mark.POINT" restriction Plot.encode's own
    # single-plot path already enforces (see _render_generic's own
    # validation) -- render_layers() raises the same way rather than
    # silently ignoring a LINE/AREA layer's own color/color_categories/
    # size, which the pre-per-point-encoding version of this function
    # used to do (see render_layers()'s own docstring).
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var line_cats: List[String] = ["a", "b"]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y, color_categories=line_cats))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_layers_with_empty_list_and_a_title_is_still_a_noop() raises:
    # test_render_layers_with_empty_list_is_a_noop's own case, but
    # confirming the new Plot.labels() support doesn't break it: an
    # empty plots list has no plots[0] to source a title from, so
    # render_layers() must skip label handling entirely rather than
    # indexing an empty list -- still a genuine no-op, canvas untouched.
    var plots = List[Plot]()
    var c = Canvas(50, 40, Color(10, 20, 30))
    render_layers(c, plots)
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, 10)
            assert_equal(p.g, 20)
            assert_equal(p.b, 30)


def test_render_layers_raises_when_a_bar_plot_is_included() raises:
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var bar_x: List[String] = ["a", "b"]
    var bar_y: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_bar().encode_categorical(x=bar_x, y=bar_y))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_layers_with_empty_list_is_a_noop() raises:
    var plots = List[Plot]()
    var c = Canvas(50, 40, Color(10, 20, 30))
    render_layers(c, plots)
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, 10)
            assert_equal(p.g, 20)
            assert_equal(p.b, 30)


def test_render_layers_raises_when_a_lollipop_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only restriction test_render_
    # layers_raises_when_a_bar_plot_is_included already confirms for
    # Mark.BAR -- checked again for one of "Phase 2a"'s new categorical
    # marks specifically, since the raise's own check is a positive
    # allow-list (only POINT/LINE/AREA), not a deny-list that would
    # need updating per new mark -- this test exists to confirm that
    # holds in practice, not just by reading the condition.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var lolli_x: List[String] = ["a", "b"]
    var lolli_y: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_lollipop().encode_categorical(x=lolli_x, y=lolli_y))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_layers_raises_when_a_candlestick_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list test_render_layers_
    # raises_when_a_lollipop_plot_is_included already confirms holds for
    # a second "Phase 2a" mark, checked again for "Phase 2b"'s own first
    # mark -- see that test's own docstring for why this needs no change
    # to render_layers()'s own check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_candlestick().encode_candlestick(cats, one, one, one, one))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_layers_raises_when_a_bullet_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # "Phase 2b"'s second mark -- see test_render_layers_raises_when_a_
    # lollipop_plot_is_included's own docstring for why this needs no
    # change to render_layers()'s own check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var ranges: List[List[Float64]] = [[1.0], [1.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_bullet().encode_bullet(cats, one, one, ranges))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_layers_raises_when_a_gantt_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # "Phase 2b"'s third and final mark -- see test_render_layers_raises_
    # when_a_lollipop_plot_is_included's own docstring for why this
    # needs no change to render_layers()'s own check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_gantt().encode_gantt(cats, one, one))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_layers_raises_when_a_grouped_bar_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # the newest mark -- see test_render_layers_raises_when_a_lollipop_
    # plot_is_included's own docstring for why this needs no change to
    # render_layers()'s own check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_layers_raises_when_a_stacked_bar_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # the newest mark -- see test_render_layers_raises_when_a_lollipop_
    # plot_is_included's own docstring for why this needs no change to
    # render_layers()'s own check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
