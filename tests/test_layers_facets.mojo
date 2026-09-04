"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers:

- render_layers()/render_layers_svg(): shared-domain layering of
  POINT/LINE/AREA, per-layer color/size encoding and legends, and the
  raise for every unsupported mark.
- The Mark.BAR combo path (_render_bar_combo_layers): a shared
  categorical x-axis with LINE/POINT/AREA layers positioned by index,
  the forced zero baseline, bars drawn first, show_data_labels on the
  bar layer, and every raise path.
- render_facets()/render_facets_svg(): independent per-cell layout,
  titles, empty-grid/invalid-cols guards.
- render_facets(shared_y_scale=True): one y-domain from the union of
  every cell's data (linear, or log via _log_data_extent when every
  cell agrees on scale_y_log() -- #217), and every raise path.
- Plot.secondary_axis(): the mirrored right-edge axis, independent
  per-axis domains, no secondary gridlines, coexistence with a
  legend, and both raise paths.
- The secondary y-axis caption from the secondary layer's own
  .labels(y_title=...), rotated the opposite way from the primary.
- Plot.series_name() (#215): one legend row per named layer, each in
  that layer's own Theme.mark_color, in layer order, with no row for
  an unnamed layer; the secondary-axis suffix; and the same for the
  Mark.BAR combo path's bar layer.
"""

from _test_helpers import BG, _assert_color, _assert_near_color, _count_color
from canvas.color import Color
from canvas.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from dataviz.color_scale import default_categorical_palette
from dataviz.colors import CORNFLOWERBLUE, MAGENTA, RED, TOMATO
from dataviz.plot import (
    Plot,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    _build_line_path,
)
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_layers.mojo
# ---------------------------------------------------------------


def test_render_layers_shares_one_domain_across_a_line_and_a_point() raises:
    # A LINE plot (x=[0,10], y=[0,10]) layered with a POINT plot (one (5,5)
    # point, red, radius 5): the combined domain pads to [-0.5, 10.5] on
    # both axes, so the point lands at (220, 135) and the line's endpoints
    # at (74.545, 239.545) and (365.455, 30.455). Both layers are
    # .size(400, 300).
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var point_x: List[Float64] = [5.0]
    var point_y: List[Float64] = [5.0]
    var plot_a = (
        Plot()
        .mark_line()
        .encode(x=line_x, y=line_y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var plot_b = (
        Plot()
        .mark_point()
        .encode(x=point_x, y=point_y)
        .theme(Theme(mark_color=RED, point_radius=5.0))
        .size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(plot_a^)
    plots.append(plot_b^)

    var c = render_layers(plots)
    _assert_color(
        c, 220, 135, RED, "the layered point, at the shared domain's pixel"
    )

    var svg_plots = List[Plot]()
    svg_plots.append(
        Plot()
        .mark_line()
        .encode(x=line_x, y=line_y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    svg_plots.append(
        Plot()
        .mark_point()
        .encode(x=point_x, y=point_y)
        .theme(Theme(mark_color=RED, point_radius=5.0))
        .size(400, 300)
    )
    var svg = render_layers_svg(svg_plots)
    var s = svg.to_string()
    assert_true(
        '<path d="M74.545,239.545 L365.455,30.455" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>'
        in s,
        "the layered line",
    )
    assert_true(
        '<circle cx="220" cy="135" r="5" fill="#ff0000"/>' in s,
        "the layered point, same shared domain",
    )


def test_render_layers_annotate_vline_and_point_match_standalone_hand_derived_positions() raises:
    # #204: annotate_vline()/annotate_point() used to be silently dropped by
    # render_layers()/render_layers_svg() (only annotate_area()/
    # annotate_line() were wired in). A single-layer list reuses exactly
    # the same plot/theme/size as test_annotations.mojo's own standalone
    # "hand-derived position" tests for these two annotate_*() kinds, so
    # the pixel/SVG values here are identical to those: the frame this one
    # layer gets is the same continuous axis frame a standalone render of
    # the same plot would build. annotate_vline(1.5) -> px=220; the point
    # at (1.2, 15.0) -> (133, 135).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var line = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .annotate_vline(1.5, label="mid")
        .annotate_point(1.2, 15.0, label="here")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var plots: List[Plot] = [line^]

    var c = render_layers(plots)
    _assert_near_color(
        c,
        220,
        100,
        Color(150, 150, 150),
        40,
        "the vline's ink, well inside the plot height",
    )
    _assert_color(
        c, 133, 135, Color(150, 150, 150), "the point marker's center pixel"
    )

    var svg_line = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .annotate_vline(1.5, label="mid")
        .annotate_point(1.2, 15.0, label="here")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg_plots: List[Plot] = [svg_line^]
    var svg = render_layers_svg(svg_plots)
    var s = svg.to_string()
    assert_true(
        '<line x1="220" y1="20" x2="220" y2="250" stroke="#969696"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "the vertical reference line itself",
    )
    assert_true(
        '<text x="224" y="32" font-size="12.000" font-family="sans-serif"'
        ' fill="#969696" text-anchor="start">mid</text>'
        in s,
        "the vline's label",
    )
    assert_true(
        '<circle cx="133" cy="135" r="4" fill="#969696"/>' in s,
        "the point marker itself",
    )
    assert_true(
        '<text x="133" y="127" font-size="12.000" font-family="sans-serif"'
        ' fill="#969696" text-anchor="middle">here</text>'
        in s,
        "the point's label",
    )


def test_render_layers_svg_annotate_band_and_best_fit_draw_against_the_layers_frame() raises:
    # #204: annotate_band()/annotate_best_fit() used to be silently dropped
    # the same way. x=[1,2,3,4], y=[10,12,13,15] on a single-layer list;
    # OLS gives slope=1.6, intercept=8.5 (n=4, sum_x=10, sum_y=50,
    # sum_xy=133, sum_xx=30: slope=(4*133-10*50)/(4*30-100)=32/20=1.6,
    # intercept=12.5-1.6*2.5=8.5), matching the label text asserted below.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [10.0, 12.0, 13.0, 15.0]
    var band_x: List[Float64] = [1.0, 4.0]
    var band_lo: List[Float64] = [8.0, 13.0]
    var band_hi: List[Float64] = [12.0, 17.0]
    var line = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .annotate_band(x=band_x, y_lower=band_lo, y_upper=band_hi, label="band")
        .annotate_best_fit(show_equation=True)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var plots: List[Plot] = [line^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        '<path d="M74.545,155.909 L365.455,20.000 L365.455,114.091'
        ' L74.545,250.000 Z" fill="#e0ecf6" fill-opacity="0.784"/>'
        in s,
        "the confidence band's filled region",
    )
    assert_true(
        '<line x1="60" y1="245" x2="380" y2="25" stroke="#969696"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "the best-fit line",
    )
    assert_true(
        '<text x="376" y="32" font-size="12.000" font-family="sans-serif"'
        ' fill="#969696" text-anchor="end">y = 1.600x + 8.500</text>'
        in s,
        "the best-fit line's equation label",
    )


def test_render_layers_svg_title_from_plots0_centers_on_shared_inner_rect() raises:
    # Same LINE+POINT setup with plots[0] setting a title: the title comes
    # from plots[0] only, and its extra_top=22 reservation shifts the
    # shared plot_y0 from 20 to 42 for every layer (the point's cy moves
    # from 135 to 146; the line's endpoints re-solve against range_max=42).
    # The title centers at ((60+380)//2, Int(18.0*0.8)) = (220, 14).
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var point_x: List[Float64] = [5.0]
    var point_y: List[Float64] = [5.0]
    var plots = List[Plot]()
    plots.append(
        Plot()
        .mark_line()
        .encode(x=line_x, y=line_y)
        .labels(title="Combined")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    plots.append(
        Plot()
        .mark_point()
        .encode(x=point_x, y=point_y)
        .theme(Theme(mark_color=RED, point_radius=5.0))
        .size(400, 300)
    )
    var svg = render_layers_svg(plots)
    var s = svg.to_string()

    assert_true(
        '<text x="220" y="14" font-size="18.000" font-family="sans-serif"'
        ' font-weight="bold" fill="#282828"'
        ' text-anchor="middle">Combined</text>'
        in s,
        "layered chart title, from plots[0], centered on the shared inner rect",
    )
    assert_true(
        '<path d="M74.545,240.545 L365.455,51.455" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>'
        in s,
        (
            "the layered line, re-solved against the title-shrunk shared inner"
            " rect"
        ),
    )
    assert_true(
        '<circle cx="220" cy="146" r="5" fill="#ff0000"/>' in s,
        (
            "the layered point, same shared domain, shifted down by the shared"
            " title reservation"
        ),
    )


def test_render_layers_svg_point_layer_color_categories_matches_hand_derived_legend() raises:
    # A single Mark.POINT layer with color_categories encoding. x=[0,10],
    # y=[0.0,0.0] (domain padded to [-1,1]), color_categories=["A","B"]:
    # short labels, so the default 130px legend width applies and
    # plot_x1=250.
    #
    # x-domain [-0.5,10.5] with plot_x0=60, plot_x1=250: to_pixel(0)=68.636
    # -> 69, to_pixel(10)=241.364 -> 241; y=0.0 lands at 135. Point 0
    # ("A") gets #1f77b4, point 1 ("B") #ff7f0e.
    #
    # Legend at legend_x=270, row 0 at y=20, row 1 at y=42.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var plots = List[Plot]()
    plots.append(
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cats)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_layers_svg(plots)
    var s = svg.to_string()

    assert_true(
        '<circle cx="69" cy="135" r="4" fill="#1f77b4"/>' in s,
        "layered point 0, category A's color",
    )
    assert_true(
        '<circle cx="241" cy="135" r="4" fill="#ff7f0e"/>' in s,
        "layered point 1, category B's color",
    )
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "legend row 0 -- narrowed plot area makes room for the legend column",
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "legend row 1",
    )


def test_render_layers_raises_when_a_line_layer_uses_color_categories() raises:
    # The same "only Mark.POINT" restriction as the single-plot path:
    # render_layers() raises for a LINE/AREA layer with
    # color/color_categories/size.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var line_cats: List[String] = ["a", "b"]
    var plots = List[Plot]()
    plots.append(
        Plot()
        .mark_line()
        .encode(x=line_x, y=line_y, color_categories=line_cats)
    )
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_with_empty_list_and_a_title_raises() raises:
    # render_layers() builds its own canvas from the plots list, so an
    # empty list has no size to derive and raises.
    var plots = List[Plot]()
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_no_longer_raises_when_a_single_bar_plot_is_included() raises:
    # Mark.BAR used to be rejected here; exactly one Mark.BAR layer now
    # dispatches to _render_bar_combo_layers (see the bar-combo tests), so
    # this is no longer a raise test.
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
    # render_layers()'s POINT/LINE/AREA allow-list, checked for
    # Mark.LOLLIPOP: every categorical mark other than Mark.BAR still falls
    # through to this check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var lolli_x: List[String] = ["a", "b"]
    var lolli_y: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(
        Plot().mark_lollipop().encode_categorical(x=lolli_x, y=lolli_y)
    )
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_raises_when_a_candlestick_plot_is_included() raises:
    # The same allow-list checked for Mark.CANDLESTICK.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(
        Plot().mark_candlestick().encode_candlestick(cats, one, one, one, one)
    )
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_raises_when_a_bullet_plot_is_included() raises:
    # The same allow-list checked for Mark.BULLET.
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
    # The same allow-list checked for Mark.GANTT.
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
    # The same allow-list checked for Mark.GROUPED_BAR.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(
        Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values)
    )
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_raises_when_a_stacked_bar_plot_is_included() raises:
    # The same allow-list checked for Mark.STACKED_BAR.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(
        Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values)
    )
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_line_honors_theme_line_smoothing() raises:
    # Both paths go through _draw_line_layer/_build_line_path, so a
    # single-layer render_layers() must match render() of the same plot
    # exactly; a layer building its own Path inline would ignore
    # Theme.line_smoothing.
    #
    # Same setup as
    # test_render_line_smoothing_bows_the_curve_away_from_the_straight_path
    # (see its comment for (147,135)); with one layer the combined domain
    # is that plot's own. Both plots use .size(400, 300).
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var theme = Theme(line_smoothing=1.0, show_gridlines=False)

    var plots = List[Plot]()
    plots.append(
        Plot().mark_line().encode(x=x, y=y).theme(theme).size(400, 300)
    )
    var c_layered = render_layers(plots)

    var _hoisted1 = (
        Plot().mark_line().encode(x=x, y=y).theme(theme).size(400, 300)
    )
    var c_standalone = render(_hoisted1)

    for yy in range(c_layered.height):
        for xx in range(c_layered.width):
            var p_layered = c_layered.get_pixel(xx, yy)
            var p_standalone = c_standalone.get_pixel(xx, yy)
            assert_equal(p_layered.r, p_standalone.r)
            assert_equal(p_layered.g, p_standalone.g)
            assert_equal(p_layered.b, p_standalone.b)

    # ...and the shared output is the curved one: the straight path's
    # segment midpoint is background under a fully smoothed curve.
    var mid = c_layered.get_pixel(147, 135)
    assert_equal(mid.r, BG.r)
    assert_equal(mid.g, BG.g)
    assert_equal(mid.b, BG.b)


def test_render_layers_area_honors_theme_line_smoothing() raises:
    # The same check for Mark.AREA, whose y-domain is forced through zero,
    # confirming _zero_baseline_y_extent survives the single-layer round
    # trip.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var theme = Theme(line_smoothing=1.0, show_gridlines=False)

    var plots = List[Plot]()
    plots.append(
        Plot().mark_area().encode(x=x, y=y).theme(theme).size(400, 300)
    )
    var c_layered = render_layers(plots)

    var _hoisted2 = (
        Plot().mark_area().encode(x=x, y=y).theme(theme).size(400, 300)
    )
    var c_standalone = render(_hoisted2)

    for yy in range(c_layered.height):
        for xx in range(c_layered.width):
            var p_layered = c_layered.get_pixel(xx, yy)
            var p_standalone = c_standalone.get_pixel(xx, yy)
            assert_equal(p_layered.r, p_standalone.r)
            assert_equal(p_layered.g, p_standalone.g)
            assert_equal(p_layered.b, p_standalone.b)


def test_render_layers_raises_on_out_of_range_smoothing() raises:
    # The same [0.0, 1.0] guard render() applies, shared through
    # _draw_line_layer.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]

    var low = List[Plot]()
    low.append(
        Plot().mark_line().encode(x=x, y=y).theme(Theme(line_smoothing=-0.1))
    )
    with assert_raises():
        _ = render_layers(low)

    var high = List[Plot]()
    high.append(
        Plot().mark_area().encode(x=x, y=y).theme(Theme(line_smoothing=1.1))
    )
    with assert_raises():
        _ = render_layers(high)


def test_render_layers_svg_named_layers_get_one_legend_row_each_in_order() raises:
    # #215: three layers, two named -- exactly two legend rows, each in
    # that layer's own Theme.mark_color, in the order the layers were
    # given; the unnamed layer draws no row at all.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y1: List[Float64] = [1.0, 2.0, 3.0]
    var y2: List[Float64] = [3.0, 2.0, 1.0]
    var y3: List[Float64] = [2.0, 2.0, 2.0]
    var a = (
        Plot()
        .mark_line()
        .encode(x=x, y=y1)
        .theme(Theme(mark_color=CORNFLOWERBLUE))
        .series_name("A")
        .size(400, 300)
    )
    var b = (
        Plot()
        .mark_line()
        .encode(x=x, y=y2)
        .theme(Theme(mark_color=TOMATO))
        .series_name("B")
        .size(400, 300)
    )
    var c = (
        Plot()
        .mark_line()
        .encode(x=x, y=y3)
        .theme(Theme(mark_color=RED))
        .size(400, 300)
    )  # unnamed
    var plots: List[Plot] = [a^, b^, c^]
    var s = render_layers_svg(plots).to_string()
    var a_idx = s.find(">A<")
    var b_idx = s.find(">B<")
    assert_true(a_idx != -1, "layer A's legend row draws")
    assert_true(b_idx != -1, "layer B's legend row draws")
    assert_true(a_idx < b_idx, "rows draw in the layers' own order")
    assert_true(
        'fill="#6495ed"' in s, "A's swatch uses its own layer's mark_color"
    )
    assert_true(
        'fill="#ff6347"' in s, "B's swatch uses its own layer's mark_color"
    )
    assert_equal(
        s.count('<rect x="') - 1, 2
    )  # the canvas background rect, plus exactly 2 swatches


def test_render_layers_svg_no_named_layers_draws_no_legend_at_all() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var a = Plot().mark_line().encode(x=x, y=y).size(400, 300)
    var b = Plot().mark_point().encode(x=x, y=y).size(400, 300)
    var plots: List[Plot] = [a^, b^]
    var s = render_layers_svg(plots).to_string()
    assert_equal(
        s.count('<rect x="'), 1
    )  # only the canvas background rect -- no legend swatch


def test_render_layers_svg_secondary_axis_layer_name_is_suffixed() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var primary = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .series_name("Primary")
        .size(400, 300)
    )
    var secondary = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .series_name("Secondary")
        .secondary_axis()
        .size(400, 300)
    )
    var plots: List[Plot] = [primary^, secondary^]
    var s = render_layers_svg(plots).to_string()
    assert_true(">Primary<" in s, "the primary layer's plain name draws")
    assert_true(
        "Secondary (right axis)" in s,
        "the secondary layer's name is suffixed so its axis is clear",
    )


# ---------------------------------------------------------------
# from tests/test_layers_bar_combo.mojo
# ---------------------------------------------------------------


def test_render_layers_svg_bar_combo_matches_hand_derived_positions() raises:
    # 2 categories, canvas 400x300, no gridlines: plot rect x:[60,380]
    # y:[20,250]. Bar y=[10,20], line y=[15,5] (its x=[0,1] is never
    # read). combined_y=[10,20,15,5] -> zero-baseline domain [0,21], range
    # [250,20], slope -10.952. Bar A (10): 140.48 -> rect y=140; Bar B
    # (20): 30.95 -> y=31. OrdinalScale over 2 categories, range [60,380]:
    # bandwidth=128, center(0)=140, center(1)=300. Line: (140, 85.714),
    # (300, 195.238).
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        '<rect x="76" y="140" width="128" height="109" fill="#1e64b4"/>' in s,
        "bar A",
    )
    assert_true(
        '<rect x="236" y="31" width="128" height="218" fill="#1e64b4"/>' in s,
        "bar B",
    )
    assert_true(
        '<path d="M140.000,85.714 L300.000,195.238" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>'
        in s,
        "the line, positioned by category index, not its own x values",
    )


def test_render_layers_svg_bar_combo_draws_the_bar_layer_first() raises:
    # The bar layer's <rect>s appear before the line's <path> regardless of
    # the bar layer's position in `plots`; the line is listed first here to
    # exercise that.
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var bars = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var plots: List[Plot] = [line^, bars^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    var rect_index = s.find('<rect x="76" y="140"')
    var path_index = s.find("<path d=")
    assert_true(
        rect_index != -1 and path_index != -1 and rect_index < path_index,
        "bar rects precede the line path",
    )


def test_render_layers_svg_bar_combo_supports_a_point_layer() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var point_y: List[Float64] = [15.0, 5.0]
    var bars = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var points = Plot().mark_point().encode(x=idx, y=point_y).size(400, 300)
    var plots: List[Plot] = [bars^, points^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        'cx="140" cy="86"' in s,
        "point A, at its category's band center (85.714 rounds to 86)",
    )
    assert_true('cx="300" cy="195"' in s, "point B (195.238 rounds to 195)")


def test_render_layers_svg_bar_combo_supports_an_area_layer() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var area_y: List[Float64] = [15.0, 5.0]
    var bars = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var area = Plot().mark_area().encode(x=idx, y=area_y).size(400, 300)
    var plots: List[Plot] = [bars^, area^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    # Closed down to the zero baseline (pixel 250), pulled 1px to 249 since
    # the baseline lands on the axis line, as _draw_area_layer does.
    assert_true(
        '<path d="M140.000,85.714 L300.000,195.238 L300.000,249.000'
        ' L140.000,249.000 Z" fill="#1e64b4"/>'
        in s,
        "the area, closed down to the shared zero baseline",
    )


def test_render_layers_svg_bar_combo_supports_show_data_labels() raises:
    # Theme.show_data_labels on the bar layer's own Theme, through
    # _draw_bar_rects. Same frame as the positions test: bar A rect y=140
    # -> label baseline 136 at x=140; bar B rect y=31 -> baseline 27 at
    # x=300.
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(Theme(show_gridlines=False, show_data_labels=True))
        .size(400, 300)
    )
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        '<text x="140" y="136" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">10</text>'
        in s,
        "bar A's own data label",
    )
    assert_true(
        '<text x="300" y="27" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">20</text>'
        in s,
        "bar B's own data label",
    )


def test_render_layers_raises_on_a_second_bar_layer() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var bars1 = (
        Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    )
    var bars2 = (
        Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    )
    var plots: List[Plot] = [bars1^, bars2^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_a_non_bar_layer_length_mismatch() raises:
    var cats: List[String] = ["A", "B", "C"]
    var bar_y: List[Float64] = [10.0, 20.0, 15.0]
    var bad_idx: List[Float64] = [0.0, 1.0]
    var bad_y: List[Float64] = [5.0, 6.0]
    var bars = (
        Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    )
    var line = Plot().mark_line().encode(x=bad_idx, y=bad_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_secondary_axis_in_a_bar_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = (
        Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    )
    var line = (
        Plot()
        .mark_line()
        .encode(x=idx, y=line_y)
        .size(400, 300)
        .secondary_axis()
    )
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_scale_y_log_in_a_bar_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [1.0, 2.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = (
        Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    )
    var line = (
        Plot().mark_line().encode(x=idx, y=line_y).size(400, 300).scale_y_log()
    )
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_color_categories_on_a_non_bar_layer() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var color_cats: List[String] = ["x", "y"]
    var bars = (
        Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    )
    var points = (
        Plot()
        .mark_point()
        .encode(x=idx, y=line_y, color_categories=color_cats)
        .size(400, 300)
    )
    var plots: List[Plot] = [bars^, points^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_annotate_line_in_a_bar_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = (
        Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    )
    var line = (
        Plot()
        .mark_line()
        .encode(x=idx, y=line_y)
        .size(400, 300)
        .annotate_line(15.0)
    )
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_annotate_band_in_a_bar_combo() raises:
    # #204: annotate_band()/annotate_best_fit() weren't part of the
    # has_annotations guard at all, so a bar-combo layer using either used
    # to render with no annotation drawn and no error -- the same
    # silent-drop bug the standalone annotate_line() check above already
    # guarded against for the other four annotate_*() kinds.
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var band_x: List[Float64] = [0.0, 1.0]
    var band_lo: List[Float64] = [1.0, 2.0]
    var band_hi: List[Float64] = [3.0, 4.0]
    var bars = (
        Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    )
    var line = (
        Plot()
        .mark_line()
        .encode(x=idx, y=line_y)
        .size(400, 300)
        .annotate_band(x=band_x, y_lower=band_lo, y_upper=band_hi)
    )
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_annotate_best_fit_in_a_bar_combo() raises:
    # See test_render_layers_raises_on_annotate_band_in_a_bar_combo above.
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = (
        Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    )
    var line = (
        Plot()
        .mark_line()
        .encode(x=idx, y=line_y)
        .size(400, 300)
        .annotate_best_fit()
    )
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_svg_bar_combo_named_layers_get_a_legend_row_each() raises:
    # #215: the bar-combo path (_render_bar_combo_layers) needs the same
    # per-layer legend the generic path has -- the bar layer included.
    var cats: List[String] = ["A", "B", "C"]
    var bar_y: List[Float64] = [10.0, 20.0, 15.0]
    var idx: List[Float64] = [0.0, 1.0, 2.0]
    var line_y: List[Float64] = [5.0, 8.0, 12.0]
    var bars = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(Theme(mark_color=CORNFLOWERBLUE))
        .series_name("Sales")
        .size(400, 300)
    )
    var line = (
        Plot()
        .mark_line()
        .encode(x=idx, y=line_y)
        .theme(Theme(mark_color=TOMATO))
        .series_name("Trend")
        .size(400, 300)
    )
    var plots: List[Plot] = [bars^, line^]
    var s = render_layers_svg(plots).to_string()
    assert_true(">Sales<" in s, "the bar layer's own legend row draws")
    assert_true(">Trend<" in s, "the line layer's own legend row draws")
    assert_true(
        'fill="#6495ed"' in s, "the bar layer's swatch uses its own mark_color"
    )


# ---------------------------------------------------------------
# from tests/test_facets.mojo
# ---------------------------------------------------------------


def test_render_facets_lays_out_independent_plots_side_by_side() raises:
    # Two cells, 400x300 each, side by side on an 800x300 canvas (cols=2).
    # Cell 0 is the single-(5.0, 5.0)-point setup: plot area x:[60,380],
    # y:[20,250], point at (220, 135). Cell 1 is the same geometry shifted
    # +400 in x: plot area x:[460,780], point at (620, 135). Two different
    # mark_colors confirm each cell rendered its own plot. The 800x300
    # canvas comes from each plot's .size(400, 300).
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy).size(400, 300)
    var plot1 = (
        Plot()
        .mark_point()
        .encode(x=xy, y=xy)
        .theme(Theme(mark_color=RED))
        .size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var c = render_facets(plots, cols=2)

    _assert_color(
        c, 220, 135, Theme.default().mark_color, "cell 0's point, unshifted"
    )
    _assert_color(c, 620, 135, RED, "cell 1's point, +400px shifted")


def test_render_facets_svg_draws_annotate_vline_and_best_fit_in_different_cells() raises:
    # #204: render_facets()/render_facets_svg() used to draw only
    # annotate_area()/annotate_line() per cell; annotate_vline()/
    # annotate_point()/annotate_band()/annotate_best_fit() were silently
    # dropped. Cell 0 (a Mark.LINE plot with annotate_vline(1.5)) reuses
    # the same geometry as the standalone/layers hand-derived vline
    # position (px=220); cell 1 (a Mark.POINT plot with
    # annotate_best_fit()) sits at cell 1's origin (+400px), where the
    # best-fit line for x=[1,2,3] y=[5,7,9] (a perfect fit, slope=2,
    # intercept=3) spans the cell's full inner width at its own padded
    # y-domain.
    var xa: List[Float64] = [1.0, 2.0]
    var ya: List[Float64] = [10.0, 20.0]
    var cell_a = (
        Plot()
        .mark_line()
        .encode(x=xa, y=ya)
        .annotate_vline(1.5)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var xb: List[Float64] = [1.0, 2.0, 3.0]
    var yb: List[Float64] = [5.0, 7.0, 9.0]
    var cell_b = (
        Plot()
        .mark_point()
        .encode(x=xb, y=yb)
        .annotate_best_fit()
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var plots: List[Plot] = [cell_a^, cell_b^]
    var svg = render_facets_svg(plots, cols=2)
    var s = svg.to_string()
    assert_true(
        '<line x1="220" y1="20" x2="220" y2="250" stroke="#969696"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        (
            "cell 0's vline, at the same pixel a standalone render of the same"
            " plot would use"
        ),
    )
    assert_true(
        '<line x1="460" y1="250" x2="780" y2="20" stroke="#969696"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "cell 1's best-fit line, spanning its own +400px-shifted inner rect",
    )


def test_render_facets_leaves_trailing_cells_blank_when_plots_dont_fill_the_grid() raises:
    # 3 plots, cols=2 -> a 2x2 grid of 400x300 cells on 800x600. Plots fill
    # row-major: (0,0), (0,1), (1,0); (1,1) is never touched. Each filled
    # cell reuses the single-point geometry offset by its cell origin:
    # (220,135), (620,135), (220,435). Every plot's background is
    # (10,20,30), so an untouched cell (the canvas's white default) is
    # distinguishable from a rendered one.
    var xy: List[Float64] = [5.0]
    var theme = Theme(background=Color(10, 20, 30))
    var plot0 = (
        Plot().mark_point().encode(x=xy, y=xy).theme(theme).size(400, 300)
    )
    var plot1 = (
        Plot().mark_point().encode(x=xy, y=xy).theme(theme).size(400, 300)
    )
    var plot2 = (
        Plot().mark_point().encode(x=xy, y=xy).theme(theme).size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)
    plots.append(plot2^)

    var c = render_facets(plots, cols=2)

    var mark_color = Theme.default().mark_color
    _assert_color(c, 220, 135, mark_color, "cell (0,0)'s point")
    _assert_color(c, 620, 135, mark_color, "cell (0,1)'s point")
    _assert_color(c, 220, 435, mark_color, "cell (1,0)'s point")
    _assert_color(
        c,
        700,
        450,
        Color(255, 255, 255),
        (
            "cell (1,1) has no 4th plot -- never touched, stays the canvas's"
            " own white default"
        ),
    )


def test_render_facets_raises_on_non_positive_cols() raises:
    # A non-empty, uniformly sized list, so cols<=0 is what raises, not the
    # empty-list guard.
    var xy: List[Float64] = [5.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_point().encode(x=xy, y=xy).size(400, 300))
    with assert_raises():
        _ = render_facets(plots, cols=0)
    with assert_raises():
        _ = render_facets(plots, cols=-1)


def test_render_facets_with_empty_list_raises() raises:
    # render_facets() builds its own canvas from the plots list, so an
    # empty list has no size to derive and raises.
    var plots = List[Plot]()
    with assert_raises():
        _ = render_facets(plots, cols=2)


def test_render_facets_svg_lays_out_independent_plots_side_by_side() raises:
    # The same two-cell setup as the raster test: cell 0's point at
    # (220, 135), cell 1's at (620, 135). Two mark_colors confirm each cell
    # rendered into the shared SvgCanvas.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy).size(400, 300)
    var plot1 = (
        Plot()
        .mark_point()
        .encode(x=xy, y=xy)
        .theme(Theme(mark_color=RED))
        .size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var svg = render_facets_svg(plots, cols=2)
    var s = svg.to_string()

    assert_true(
        '<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in s,
        "cell 0's point, same coordinates render_facets()'s test finds",
    )
    assert_true(
        '<circle cx="620" cy="135" r="4" fill="#ff0000"/>' in s,
        "cell 1's point, +400px shifted, same as render_facets()'s test",
    )


def test_render_facets_svg_each_cell_gets_its_own_independent_title() raises:
    # Same two-cell layout, with cell 0's Plot setting a title and cell 1's
    # not: the title reserves space only in cell 0 (extra_top=22 pushes
    # plot_y0 from 20 to 42, moving the point from (220,135) to (220,146))
    # while cell 1's point stays at (620,135). The title centers at
    # (220, 14).
    var xy: List[Float64] = [5.0]
    var plot0 = (
        Plot()
        .mark_point()
        .encode(x=xy, y=xy)
        .labels(title="Left")
        .size(400, 300)
    )
    var plot1 = (
        Plot()
        .mark_point()
        .encode(x=xy, y=xy)
        .theme(Theme(mark_color=RED))
        .size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var svg = render_facets_svg(plots, cols=2)
    var s = svg.to_string()

    assert_true(
        '<text x="220" y="14" font-size="18.000" font-family="sans-serif"'
        ' font-weight="bold" fill="#282828" text-anchor="middle">Left</text>'
        in s,
        "cell 0's title, centered on its inner plot rect",
    )
    assert_true(
        '<circle cx="220" cy="146" r="4" fill="#1e64b4"/>' in s,
        "cell 0's point, shifted down to make room for its title",
    )
    assert_true(
        '<circle cx="620" cy="135" r="4" fill="#ff0000"/>' in s,
        "cell 1's point, unaffected -- it never set a title",
    )


def test_render_facets_svg_raises_on_non_positive_cols() raises:
    var xy: List[Float64] = [5.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_point().encode(x=xy, y=xy).size(400, 300))
    with assert_raises():
        _ = render_facets_svg(plots, cols=0)


def test_render_facets_paints_each_cells_full_rect_including_a_titles_margin() raises:
    # render_facets() fills each cell's full rect, including a titled
    # cell's reserved title strip. A distinctive Theme.background (MAGENTA)
    # on the canvas's white default proves a real fill_rect reached pixel
    # (2,2); with cols=1, title_font_size=18.0 and label_gap=4,
    # extra_top=22, so y=2 is inside the reserved strip.
    var xy: List[Float64] = [5.0]
    var plots = List[Plot]()
    plots.append(
        Plot()
        .mark_point()
        .encode(x=xy, y=xy)
        .labels(title="Titled")
        .theme(Theme(background=MAGENTA))
        .size(400, 300)
    )

    var c = render_facets(plots, 1)
    _assert_color(c, 2, 2, MAGENTA, "a titled cell's reserved title strip")

    # ...and the same for an untitled cell, where the corner is still
    # outside the plot area.
    var untitled = List[Plot]()
    untitled.append(
        Plot()
        .mark_point()
        .encode(x=xy, y=xy)
        .theme(Theme(background=MAGENTA))
        .size(400, 300)
    )
    var c2 = render_facets(untitled, 1)
    _assert_color(c2, 2, 2, MAGENTA, "an untitled cell's top-left corner")


# ---------------------------------------------------------------
# from tests/test_facets_shared_scale.mojo
# ---------------------------------------------------------------


def test_render_facets_svg_shared_y_scale_matches_hand_derived_positions() raises:
    # Two cells, one point each (y=10 and y=110): combined domain [10, 110],
    # padded 5% (5.0) -> [5, 115]. Each cell is 400x300 (rows=1), default
    # theme -> plot_y0=20, plot_y1=250.
    #
    # scale() = (20-250)/(115-5) = -2.0909...
    # translate() = 250 - 5*scale() = 260.4545...
    # to_pixel(10) = 239.545 -> 240 (cell 0)
    # to_pixel(110) = 30.454 -> 30 (cell 1)
    #
    # With independent domains, cell 0's lone y=10 would be a zero-span
    # domain [9,11] landing on a different row, so this also confirms the
    # shared domain is used.
    var x: List[Float64] = [1.0]
    var y0: List[Float64] = [10.0]
    var y1: List[Float64] = [110.0]
    var p0 = Plot().size(400, 300).mark_point().encode(x=x, y=y0)
    var p1 = Plot().size(400, 300).mark_point().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    var s = render_facets_svg(plots, 2, shared_y_scale=True).to_string()
    assert_true(
        'cy="240"' in s,
        "cell 0's own point (y=10) lands at the hand-derived shared-scale row",
    )
    assert_true(
        'cy="30"' in s,
        "cell 1's own point (y=110) lands at the hand-derived shared-scale row",
    )


def test_render_facets_raises_on_an_incompatible_mark_with_shared_y_scale() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var p0 = Plot().size(300, 220).mark_bar().encode_categorical(x=cats, y=vals)
    var p1 = Plot().size(300, 220).mark_bar().encode_categorical(x=cats, y=vals)
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_raises_on_mark_area_with_shared_y_scale() raises:
    # Mark.AREA is excluded: its forced zero baseline can't compose with an
    # external shared domain.
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 6.0]
    var y1: List[Float64] = [50.0, 60.0]
    var p0 = Plot().size(300, 220).mark_area().encode(x=x, y=y0)
    var p1 = Plot().size(300, 220).mark_area().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_svg_shared_y_scale_supports_log_when_every_cell_agrees() raises:
    # #217: two log-y cells, y0=[5,6] and y1=[50,60]. Verified by
    # construction: the combined log-space domain gives both cells the
    # identical tick set 5/10/20/50 at rows 163/125/87/37 -- an
    # independent per-cell domain would put cell 0's [5,6] and cell 1's
    # [50,60] on very different scales instead.
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 6.0]
    var y1: List[Float64] = [50.0, 60.0]
    var p0 = (
        Plot()
        .size(300, 220)
        .mark_line()
        .encode(x=x, y=y0)
        .scale_y_log()
        .theme(Theme(show_gridlines=False))
    )
    var p1 = (
        Plot()
        .size(300, 220)
        .mark_line()
        .encode(x=x, y=y1)
        .scale_y_log()
        .theme(Theme(show_gridlines=False))
    )
    var plots: List[Plot] = [p0^, p1^]
    var s = render_facets_svg(plots, 2, shared_y_scale=True).to_string()
    for row in ["163", "125", "87", "37"]:
        assert_true(
            'y1="' + row + '"' in s and 'y2="' + row + '"' in s,
            "both cells share a gridline-free tick row at " + row,
        )
    assert_true(">50<" in s, "cell 1's own high value labels a shared tick")


def test_render_facets_raises_on_a_scale_y_log_mix_with_shared_y_scale() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 6.0]
    var y1: List[Float64] = [50.0, 60.0]
    var p0 = Plot().size(300, 220).mark_line().encode(x=x, y=y0).scale_y_log()
    var p1 = Plot().size(300, 220).mark_line().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_raises_on_y_err_with_shared_y_scale() raises:
    # The shared union is computed over plain plot.y_data, not widened for
    # whisker endpoints, so this combination raises. Mark.POINT, since
    # Mark.LINE doesn't support y_err in this context.
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 6.0]
    var y1: List[Float64] = [50.0, 60.0]
    var err: List[Float64] = [1.0, 1.0]
    var p0 = Plot().size(300, 220).mark_point().encode(x=x, y=y0, y_err=err)
    var p1 = Plot().size(300, 220).mark_point().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_svg_default_keeps_each_cells_independent_scale() raises:
    # shared_y_scale defaults False: two single-point cells each get their
    # own [y-1, y+1] domain, landing both points on the same row.
    var x: List[Float64] = [1.0]
    var y0: List[Float64] = [10.0]
    var y1: List[Float64] = [110.0]
    var p0 = Plot().size(400, 300).mark_point().encode(x=x, y=y0)
    var p1 = Plot().size(400, 300).mark_point().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    var s = render_facets_svg(plots, 2).to_string()
    # domain [9, 11], range [250, 20] -> to_pixel(10) = 135.0 exactly, the
    # same middle row for both cells.
    var count = 0
    var search_from = 0
    while True:
        var idx = s.find('cy="135"', search_from)
        if idx == -1:
            break
        count += 1
        search_from = idx + 1
    assert_true(
        count == 2,
        (
            "both cells' own independent domain centers their lone point at"
            " row 135"
        ),
    )


# ---------------------------------------------------------------
# from tests/test_secondary_axis.mojo
# ---------------------------------------------------------------


def test_render_layers_svg_secondary_axis_matches_hand_derived_position() raises:
    # 2 layers, no color/size encoding (legend_reserve 0), gridlines on to
    # confirm the secondary domain draws none. Canvas 400x300: the primary
    # line rises 10->20 (plot area x:[60,342], y:[20,250], px1 shrunk to
    # 350 by the secondary axis's reserve). The secondary line falls
    # 50->10, a different shape so a reused primary scale would draw a
    # visibly different path.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).size(400, 300)
    var secondary = (
        Plot().mark_line().encode(x=x, y=y2).secondary_axis().size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()

    assert_true(
        '<path d="M73.182,239.545 L336.818,30.455" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>'
        in s,
        "the primary layer's rising path, against the primary (left) y-scale",
    )
    assert_true(
        '<path d="M73.182,30.455 L336.818,239.545" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>'
        in s,
        (
            "the secondary layer's falling path -- the opposite slope, against"
            " its own independent (right) y-scale, not the primary one"
        ),
    )
    assert_true(
        '<line x1="350" y1="20" x2="350" y2="250" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        (
            "the secondary axis's vertical line, mirrored onto the plot's right"
            " edge"
        ),
    )
    assert_true(
        '<line x1="350" y1="135" x2="355" y2="135" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "one of the secondary axis's ticks, pointing right instead of left",
    )
    assert_true(
        '<text x="359" y="139" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="start">30</text>'
        in s,
        (
            "that tick's label, left-aligned just past it -- the mirror of the"
            " primary axis's right-aligned labels sitting just before its ticks"
        ),
    )


def test_render_layers_svg_secondary_axis_draws_no_gridlines_of_its_own() raises:
    # Exactly 6 gridlines: 3 vertical from the shared x-axis, 3 horizontal
    # from the primary y-domain's ticks (10/15/20). The secondary domain's
    # 5 ticks add none.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).size(400, 300)
    var secondary = (
        Plot().mark_line().encode(x=x, y=y2).secondary_axis().size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    var count = 0
    var search_from = 0
    while True:
        var idx = s.find('stroke="#e1e1e1"', search_from)
        if idx == -1:
            break
        count += 1
        search_from = idx + 1
    assert_equal(
        count,
        6,
        "only the shared x-axis's and the primary y-axis's gridlines draw",
    )


def test_render_layers_secondary_axis_raster_draws_ink_at_the_hand_derived_row() raises:
    # Raster companion: confirms draw_line_aa painted the secondary axis's
    # tick at (350, 135). Sampled at x=349, where the supersampled 1px tick
    # happens to land fully opaque.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).size(400, 300)
    var secondary = (
        Plot().mark_line().encode(x=x, y=y2).secondary_axis().size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var c = render_layers(plots)
    _assert_color(
        c,
        349,
        135,
        Color(80, 80, 80),
        "the secondary axis's tick, just right of its axis line",
    )


def test_render_layers_svg_secondary_axis_coexists_with_a_legend_without_overlap() raises:
    # A color-categories Mark.POINT primary layer (so a legend draws)
    # alongside a secondary-axis Mark.LINE layer: the legend column shifts
    # right past the secondary axis's reserved width. The secondary axis
    # lands at x=220, and its widest tick label ("50") ends before x=270,
    # where the first swatch starts.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = (
        Plot()
        .mark_point()
        .encode(x=x, y=y1, color_categories=cats)
        .size(400, 300)
    )
    var secondary = (
        Plot().mark_line().encode(x=x, y=y2).secondary_axis().size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        '<line x1="220" y1="20" x2="220" y2="250" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        (
            "the secondary axis's line, shrunk further left to also make room"
            " for the legend"
        ),
    )
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        (
            "the legend's first swatch, starting well clear of the secondary"
            " axis's labels"
        ),
    )


def test_render_secondary_axis_raises_on_standalone_render() raises:
    # Plot.secondary_axis() only means anything inside render_layers(); a
    # standalone render() raises.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = (
        Plot().mark_line().encode(x=x, y=y).secondary_axis().size(200, 150)
    )
    with assert_raises():
        _ = render(plot)


def test_render_layers_raises_when_every_layer_is_secondary() raises:
    # At least one layer must stay on the primary axis; every layer calling
    # .secondary_axis() raises.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var a = Plot().mark_line().encode(x=x, y=y1).secondary_axis()
    var b = Plot().mark_line().encode(x=x, y=y2).secondary_axis()
    var plots = List[Plot]()
    plots.append(a^)
    plots.append(b^)
    with assert_raises():
        _ = render_layers(plots)


# ---------------------------------------------------------------
# from tests/test_secondary_axis_caption.mojo
# ---------------------------------------------------------------


def test_render_layers_svg_secondary_axis_caption_matches_hand_derived_position() raises:
    # Primary layer (y:[10,20]) with no caption, secondary layer (y:[50,10])
    # captioned "Growth" via .labels(y_title=...), canvas 400x300, no
    # gridlines: the secondary axis line moves left to x=332 (from 350) to
    # make room, and the caption draws rotated +90 degrees, centered at
    # (389, 135).
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = (
        Plot()
        .mark_line()
        .encode(x=x, y=y1)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var secondary = (
        Plot()
        .mark_line()
        .encode(x=x, y=y2)
        .secondary_axis()
        .labels(y_title="Growth")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        '<text x="389" y="135" font-size="14.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle" transform="rotate(90.000 389'
        ' 135)">Growth</text>'
        in s,
        (
            "the secondary axis's caption, rotated the opposite way from the"
            " primary y_title"
        ),
    )
    assert_true(
        '<line x1="332" y1="20" x2="332" y2="250" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        (
            "the secondary axis's line, shrunk further left to also make room"
            " for its caption"
        ),
    )


def test_render_layers_svg_no_caption_when_secondary_axis_has_no_y_title() raises:
    # A secondary-axis layer with no y_title draws no caption, and the axis
    # line stays at x=350.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = (
        Plot()
        .mark_line()
        .encode(x=x, y=y1)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var secondary = (
        Plot()
        .mark_line()
        .encode(x=x, y=y2)
        .secondary_axis()
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        "rotate(90" not in s,
        "no secondary-axis caption text draws when y_title is unset",
    )
    assert_true(
        '<line x1="350" y1="20" x2="350" y2="250" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        (
            "the secondary axis's line lands at its no-caption position,"
            " unaffected"
        ),
    )


def test_render_layers_svg_primary_layers_own_y_title_is_not_mistaken_for_a_caption() raises:
    # plots[0]'s y_title still draws on the left; only a layer that called
    # .secondary_axis() gets the right-side caption.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = (
        Plot()
        .mark_line()
        .encode(x=x, y=y1)
        .labels(y_title="Primary")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var secondary = (
        Plot()
        .mark_line()
        .encode(x=x, y=y2)
        .secondary_axis()
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        "rotate(-90" in s,
        "the primary layer's y_title still draws, rotated the usual way",
    )
    assert_true(
        "rotate(90.000" not in s,
        "no right-side caption draws just because plots[0] set a y_title",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
