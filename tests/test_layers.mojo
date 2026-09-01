"""Tests for render_layers/render_layers_svg: shared-domain layering of
Mark.POINT/LINE/AREA, per-layer color/size encoding and legends, and the
raises-guards for every mark type layering doesn't support.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

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
    _index_of,
    _unique_categories,
)
from dataviz_mojo.theme import Theme
from dataviz_mojo.colors import RED

from _test_helpers import BG, _count_color, _assert_color


def test_render_layers_shares_one_domain_across_a_line_and_a_point() raises:
    # A LINE plot (x=[0,10], y=[0,10], default theme) layered with a
    # POINT plot (a single (5,5) point, custom red color + radius 5)
    # -- the combined domain (both plots' x/y data
    # together) pads to [-0.5, 10.5] on both axes, landing the shared
    # point (5,5) -- coincidentally, since 5.0 is that domain's midpoint -- on the same (220, 135) pixel many other single-plot
    # tests in this file already use, and the line's two endpoints
    # at (74.545, 239.545) and (365.455, 30.455).
    #
    # render_layers() derives its 400x300 canvas from every layer's own
    # .size(400, 300) (all layers must agree -- see _require_uniform_
    # size's docstring).
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var point_x: List[Float64] = [5.0]
    var point_y: List[Float64] = [5.0]
    var plot_a = Plot().mark_line().encode(x=line_x, y=line_y).theme(Theme(show_gridlines=False)).size(400, 300)
    var plot_b = Plot().mark_point().encode(x=point_x, y=point_y).theme(
        Theme(mark_color=RED, point_radius=5.0)
    ).size(400, 300)
    var plots = List[Plot]()
    plots.append(plot_a^)
    plots.append(plot_b^)

    var c = render_layers(plots)
    _assert_color(c, 220, 135, RED, "the layered point, at the shared domain's pixel")

    var svg_plots = List[Plot]()
    svg_plots.append(Plot().mark_line().encode(x=line_x, y=line_y).theme(Theme(show_gridlines=False)).size(400, 300))
    svg_plots.append(
        Plot().mark_point().encode(x=point_x, y=point_y).theme(
            Theme(mark_color=RED, point_radius=5.0)
        ).size(400, 300)
    )
    var svg = render_layers_svg(svg_plots)
    var s = svg.to_string()
    assert_true(
        '<path d="M74.545,239.545 L365.455,30.455" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the layered line",
    )
    assert_true('<circle cx="220" cy="135" r="5" fill="#ff0000"/>' in s, "the layered point, same shared domain")


def test_render_layers_svg_title_from_plots0_centers_on_shared_inner_rect() raises:
    # Same LINE+POINT layered setup as the test just above, now with
    # plots[0] (the LINE plot) setting a chart title via .labels() --
    # confirming render_layers()'s Plot.labels() support
    # (the wiki's Changelog, its "Plot.labels() reaches
    # render_facets/render_layers" entry): the title comes from
    # plots[0] only (the same "shared chrome from plots[0]" convention
    # Theme follows here -- see render_layers()'s docstring), and its extra_top=Int(18.0)+4=22 reservation
    # shifts the *shared* plot_y0 from 20 to 42 -- affecting every
    # layer's geometry together, not just plots[0]'s own, since
    # every layer draws into the identical shared inner rect (the
    # point's cy moves from 135 to 146; the line's endpoints
    # re-solved below via the same to_pixel formula the un-titled test
    # above confirmed, just against range_max=42 instead of 20).
    # Title itself centers at ((60+380)//2, Int(18.0*0.8))=(220,14).
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var point_x: List[Float64] = [5.0]
    var point_y: List[Float64] = [5.0]
    var plots = List[Plot]()
    plots.append(
        Plot().mark_line().encode(x=line_x, y=line_y).labels(title="Combined").theme(
            Theme(show_gridlines=False)
        ).size(400, 300)
    )
    plots.append(
        Plot().mark_point().encode(x=point_x, y=point_y).theme(
            Theme(mark_color=RED, point_radius=5.0)
        ).size(400, 300)
    )
    var svg = render_layers_svg(plots)
    var s = svg.to_string()

    assert_true(
        '<text x="220" y="14" font-size="18.000" font-family="sans-serif" font-weight="bold" fill="#282828"'
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
    # encoding -- confirming render_layers()'s per-point encoding +
    # legend support (the wiki's Changelog, its "render_layers
    # per-point encoding and legends" entry). x=[0,10], y=[0.0,0.0]
    # (constant -- zero-span domain, padded to [-1,1], the same pattern
    # test_render_color_encoding_matches_hand_derived_colors above
    # establishes), color_categories=["A","B"] -- short labels,
    # so the default 130px Theme.legend_width governs (not grown), and
    # plot_x1 becomes 400-20-130=250 (not 380, the no-legend value other
    # single-layer tests in this file use).
    #
    # x-domain pads [0,10] to [-0.5,10.5]; with plot_x0=60 (unaffected,
    # no dynamic left-margin growth -- short y=[-1,1] tick labels) and
    # this narrowed plot_x1=250, to_pixel(0)=68.636->69,
    # to_pixel(10)=241.364->241 (re-solved via the same LinearScale
    # slope/intercept formula every hand-derived pixel test in this file
    # uses, cross-checked in Python, not read off the code's output). y=[−1,1] domain's midpoint (value 0.0) lands at the
    # exact vertical center of [plot_y0=20, plot_y1=250] -> 135, for
    # both points (constant y). Point 0 ("A") gets the default palette's
    # first color (#1f77b4), point 1 ("B") the second (#ff7f0e) --
    # the identical two colors/ordering the single-plot categorical-
    # color tests in this file confirm, reused unchanged since
    # render_layers's per-layer encoding is exactly Mark.POINT's single-plot logic, not a reimplementation.
    #
    # Legend column at legend_x=plot_x1+margin_right=250+20=270, row 0
    # (swatch "A") at y=plot_y0=20, row 1 ("B") at y=20+(14+8)=42 -- the
    # identical swatch_size=14/row_gap=8 spacing test_render_point_
    # legend_width_grows_to_fit_long_category_names above
    # establishes.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var plots = List[Plot]()
    plots.append(
        Plot().mark_point().encode(x=x, y=y, color_categories=cats).theme(Theme(show_gridlines=False)).size(400, 300)
    )
    var svg = render_layers_svg(plots)
    var s = svg.to_string()

    assert_true('<circle cx="69" cy="135" r="4" fill="#1f77b4"/>' in s, "layered point 0, category A's color")
    assert_true('<circle cx="241" cy="135" r="4" fill="#ff7f0e"/>' in s, "layered point 1, category B's color")
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "legend row 0 -- narrowed plot area makes room for the legend column",
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "legend row 1",
    )


def test_render_layers_raises_when_a_line_layer_uses_color_categories() raises:
    # The identical "only Mark.POINT" restriction Plot.encode's
    # single-plot path already enforces (see _render_generic's
    # validation) -- render_layers() raises the same way rather than
    # silently ignoring a LINE/AREA layer's color/color_categories/
    # size. A single-element list is trivially uniform-sized (default
    # 640x420, never set explicitly) -- irrelevant here since the
    # mark-type check raises before size would matter.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var line_cats: List[String] = ["a", "b"]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y, color_categories=line_cats))
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_with_empty_list_and_a_title_raises() raises:
    # A prior version of this function took a caller-supplied canvas
    # and treated an empty plots list (with or without a title-bearing
    # plots[0], which doesn't exist for an empty list either way) as a
    # no-op against it; now that render_layers() builds its own canvas
    # from the plots list, there's no plot left to derive a size (or a
    # title) from, so an empty list raises instead (see _require_
    # uniform_size's docstring).
    var plots = List[Plot]()
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_no_longer_raises_when_a_single_bar_plot_is_included() raises:
    # Mark.BAR used to be a plain deny-listed mark here, same as every
    # other categorical-x-axis mark below -- render_layers()'s own
    # bar-combo path (_render_bar_combo_layers, plot.mojo) now handles
    # exactly one Mark.BAR layer instead of rejecting it outright (see
    # tests/test_layers_bar_combo.mojo for that path's own dedicated,
    # hand-derived coverage) -- this is deliberately no longer a raise
    # test, confirming the lift actually took effect rather than
    # leaving a stale assertion pointing at removed behavior.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var bar_x: List[String] = ["a", "b"]
    var bar_y: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_bar().encode_categorical(x=bar_x, y=bar_y))
    _ = render_layers(plots)


def test_render_layers_with_empty_list_raises() raises:
    var plots = List[Plot]()
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_raises_when_a_lollipop_plot_is_included() raises:
    # render_layers()'s Mark.POINT/LINE/AREA-only allow-list, checked
    # for Mark.LOLLIPOP -- unlike Mark.BAR (now specially handled by
    # _render_bar_combo_layers, see test_render_layers_no_longer_
    # raises_when_a_single_bar_plot_is_included), every other
    # categorical-x-axis mark still falls straight through to this
    # plain deny-by-omission check, unaffected by that carve-out. This
    # test exists to confirm that holds in practice, not just by
    # reading the condition.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var lolli_x: List[String] = ["a", "b"]
    var lolli_y: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_lollipop().encode_categorical(x=lolli_x, y=lolli_y))
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_raises_when_a_candlestick_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # Mark.CANDLESTICK -- see test_render_layers_raises_when_a_
    # lollipop_plot_is_included's docstring for why this needs no
    # change to render_layers()'s check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_candlestick().encode_candlestick(cats, one, one, one, one))
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_raises_when_a_bullet_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # Mark.BULLET -- see test_render_layers_raises_when_a_
    # lollipop_plot_is_included's docstring for why this needs no
    # change to render_layers()'s check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var ranges: List[List[Float64]] = [[1.0], [1.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_bullet().encode_bullet(cats, one, one, ranges))
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_raises_when_a_gantt_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # Mark.GANTT -- see test_render_layers_raises_when_a_lollipop_
    # plot_is_included's docstring for why this needs no change to
    # render_layers()'s check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_gantt().encode_gantt(cats, one, one))
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_raises_when_a_grouped_bar_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # Mark.GROUPED_BAR -- see test_render_layers_raises_when_a_lollipop_
    # plot_is_included's docstring for why this needs no change to
    # render_layers()'s check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values))
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_raises_when_a_stacked_bar_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # Mark.STACKED_BAR -- see test_render_layers_raises_when_a_lollipop_
    # plot_is_included's docstring for why this needs no change to
    # render_layers()'s check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values))
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_line_honors_theme_line_smoothing() raises:
    # Both paths go through _draw_line_layer/_build_line_path, so a
    # single-layer render_layers() must match render() of that same
    # plot exactly. Guards against the two drifting apart again: a
    # layer building its own Path inline instead would silently ignore
    # Theme.line_smoothing, always drawing straight segments no matter
    # what it asked for, while the identical plot through render()
    # curved.
    #
    # Exactly test_render_line_smoothing_bows_the_curve_away_from_the_
    # straight_path's setup (test_line.mojo -- see its comment for
    # where (147,135) comes from): one layer means the combined domain
    # is just that plot's own, so every pixel it hand-derived applies
    # here unchanged. Both the layered and standalone plots share the
    # same explicit .size(400, 300) so their canvases -- and the
    # hand-derived (147, 135) pixel -- line up.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var theme = Theme(line_smoothing=1.0, show_gridlines=False)

    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=x, y=y).theme(theme).size(400, 300))
    var c_layered = render_layers(plots)

    var _hoisted1 = Plot().mark_line().encode(x=x, y=y).theme(theme).size(400, 300)
    var c_standalone = render(_hoisted1)

    for yy in range(c_layered.height):
        for xx in range(c_layered.width):
            var p_layered = c_layered.get_pixel(xx, yy)
            var p_standalone = c_standalone.get_pixel(xx, yy)
            assert_equal(p_layered.r, p_standalone.r)
            assert_equal(p_layered.g, p_standalone.g)
            assert_equal(p_layered.b, p_standalone.b)

    # .and that the shared output is genuinely the *curved* one, not
    # two identically-straight renders agreeing with each other: the
    # straight path's segment midpoint is background under a fully
    # smoothed curve.
    var mid = c_layered.get_pixel(147, 135)
    assert_equal(mid.r, BG.r)
    assert_equal(mid.g, BG.g)
    assert_equal(mid.b, BG.b)


def test_render_layers_area_honors_theme_line_smoothing() raises:
    # test_render_layers_line_honors_theme_line_smoothing's case
    # for Mark.AREA, which had the identical inline-Path problem (and
    # whose y-domain, unlike LINE's, is forced through zero -- so this
    # also confirms the shared _zero_baseline_y_extent rule survives
    # the single-layer round trip).
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var theme = Theme(line_smoothing=1.0, show_gridlines=False)

    var plots = List[Plot]()
    plots.append(Plot().mark_area().encode(x=x, y=y).theme(theme).size(400, 300))
    var c_layered = render_layers(plots)

    var _hoisted2 = Plot().mark_area().encode(x=x, y=y).theme(theme).size(400, 300)
    var c_standalone = render(_hoisted2)

    for yy in range(c_layered.height):
        for xx in range(c_layered.width):
            var p_layered = c_layered.get_pixel(xx, yy)
            var p_standalone = c_standalone.get_pixel(xx, yy)
            assert_equal(p_layered.r, p_standalone.r)
            assert_equal(p_layered.g, p_standalone.g)
            assert_equal(p_layered.b, p_standalone.b)


def test_render_layers_raises_on_out_of_range_smoothing() raises:
    # The same [0.0, 1.0] guard test_render_line_raises_on_out_of_range_
    # smoothing (test_line.mojo) confirms for render() -- the
    # layered path shares this check via _draw_line_layer, rejecting a
    # value Theme.line_smoothing's docstring assigns no meaning to.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]

    var low = List[Plot]()
    low.append(Plot().mark_line().encode(x=x, y=y).theme(Theme(line_smoothing=-0.1)))
    with assert_raises():
        _ = render_layers(low)

    var high = List[Plot]()
    high.append(Plot().mark_area().encode(x=x, y=y).theme(Theme(line_smoothing=1.1)))
    with assert_raises():
        _ = render_layers(high)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
