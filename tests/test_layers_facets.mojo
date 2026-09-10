"""Tests for layers and facets.

Covers:

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
  cell agrees on scale_y_log() -- ), and every raise path.
- Plot.secondary_axis(): the mirrored right-edge axis, independent
  per-axis domains, no secondary gridlines, coexistence with a
  legend, and both raise paths.
- The secondary y-axis caption from the secondary layer's own
  .labels(y_title=...), rotated the opposite way from the primary.
- Plot.series_name(): one legend row per named layer, each in
  that layer's own Theme.mark_color, in layer order, with no row for
  an unnamed layer; the secondary-axis suffix; and the same for the
  Mark.BAR combo path's bar layer.
"""

from _test_helpers import (
    BG,
    _assert_color,
    _assert_near_color,
    _bbox_of_color,
    _bbox_of_color_in,
    _count_color,
    _count_tag,
)
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.path import PathOp
from dataviz import LineStyle, StepStyle
from dataviz.color_scale import default_categorical_palette
from dataviz.barbs import barbs
from dataviz.continuous import line, scatter
from dataviz.contour import contour
from dataviz.effect_scatter import effect_scatter
from dataviz.ecdf import _ecdf_points, ecdf
from dataviz.kde import kdeplot, rugplot
from dataviz.tricontour import tricontour, tricontourf
from dataviz.triplot import tripcolor, triplot
from std.math import cos, sin
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
        '<circle cx="220.000" cy="135.000" r="5.000" fill="#ff0000"/>' in s,
        "the layered point, same shared domain",
    )


def test_render_layers_annotate_vline_and_point_match_standalone_hand_derived_positions() raises:
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
        '<line x1="220.000" y1="20.000" x2="220.000" y2="250.000"'
        ' stroke="#969696" stroke-width="1.000" stroke-linecap="round"/>'
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
        '<circle cx="132.727" cy="135.000" r="4.000" fill="#969696"/>' in s,
        "the point marker itself",
    )
    assert_true(
        '<text x="133" y="127" font-size="12.000" font-family="sans-serif"'
        ' fill="#969696" text-anchor="middle">here</text>'
        in s,
        "the point's label",
    )


def test_render_layers_svg_annotate_band_and_best_fit_draw_against_the_layers_frame() raises:
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
        ' L74.545,250.000 Z" fill="#e0ecf6"'
        ' fill-opacity="0.784"/>'
        in s,
        "the confidence band's filled region",
    )
    assert_true(
        '<line x1="60.000" y1="245.400" x2="380.000" y2="24.600"'
        ' stroke="#969696" stroke-width="1.000" stroke-linecap="round"/>'
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
        '<circle cx="220.000" cy="146.000" r="5.000" fill="#ff0000"/>' in s,
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
        '<circle cx="68.636" cy="135.000" r="4.000" fill="#1f77b4"/>' in s,
        "layered point 0, category A's color",
    )
    assert_true(
        '<circle cx="241.364" cy="135.000" r="4.000" fill="#ff7f0e"/>' in s,
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
    # three layers, two named -- exactly two legend rows, each in
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
        '<rect x="77" y="141" width="128" height="109" fill="#1e64b4"/>' in s,
        "bar A",
    )
    assert_true(
        '<rect x="237" y="31" width="128" height="219" fill="#1e64b4"/>' in s,
        "bar B",
    )
    assert_true(
        '<path d="M140.000,85.714 L300.000,195.238" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>'
        in s,
        "the line, positioned by category index, not its own x values",
    )


def test_render_layers_bar_combo_honors_the_line_style() raises:
    """The bar-combo path builds its `Mark.LINE` geometry inline
    rather than calling `_draw_line_layer`, and its stroke had no
    `dashes=`, so `mark_line(style=...)` rendered solid and silently.

    A dashed reference line drawn solid does not look like a bug -- it
    looks like another data series, which is the one thing dashing it was
    meant to deny.

    Asserted through SVG, where a dash pattern is an exact attribute
    rather than something to infer from pixels, matching
    `test_line_styles_emit_the_expected_dash_patterns`.
    """
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
    var line = (
        Plot()
        .mark_line(style=LineStyle.DASHED)
        .encode(x=idx, y=line_y)
        .size(400, 300)
    )
    var plots: List[Plot] = [bars^, line^]
    var s = render_layers_svg(plots).to_string()
    assert_true(
        'stroke-dasharray="6.000 4.000"' in s,
        "the layered line is dashed -- DASHED is 6 on, 4 off at scale 1",
    )

    # The control: the same chart with the default style must emit no
    # dash pattern. Without it this test would still pass if `dashes=`
    # were wired to a constant rather than to the layer's own style.
    var solid_bars = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var solid_line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var solid_plots: List[Plot] = [solid_bars^, solid_line^]
    assert_true(
        "stroke-dasharray" not in render_layers_svg(solid_plots).to_string(),
        "the same chart with the default style emits no dash pattern",
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
    var rect_index = s.find('<rect x="77" y="141"')
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
        'cx="140.000" cy="85.714"' in s,
        "point A, at its category's band center",
    )
    assert_true('cx="300.000" cy="195.238"' in s, "point B")


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


def test_render_layers_svg_bar_combo_honors_line_step() raises:
    # _render_bar_combo_layers builds its Mark.LINE geometry inline
    # rather than calling _draw_line_layer, so mark_line(step=...) has
    # to be threaded through here separately. Ignoring it would
    # not be a styling miss: the chart would assert a gradual slide
    # between two categories that the caller explicitly said held flat.
    #
    # Three categories on the 400x300 frame the other bar-combo tests
    # use: OrdinalScale centers at 113.333, 220.000, 326.667, and
    # combined_y=[10,20,14,15,5,12] zero-baselines to [0,21] over
    # [250,20], so line y=[15,5,12] lands at 85.714, 195.238, 118.571.
    # POST holds each y across to the next category's center.
    var cats: List[String] = ["A", "B", "C"]
    var bar_y: List[Float64] = [10.0, 20.0, 14.0]
    var idx: List[Float64] = [0.0, 1.0, 2.0]
    var line_y: List[Float64] = [15.0, 5.0, 12.0]
    var bars = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var stepped = (
        Plot()
        .mark_line(step=StepStyle.POST)
        .encode(x=idx, y=line_y)
        .size(400, 300)
    )
    var plots: List[Plot] = [bars^, stepped^]
    var s = render_layers_svg(plots).to_string()
    assert_true(
        '<path d="M113.333,85.714 L220.000,85.714 L220.000,195.238'
        ' L326.667,195.238 L326.667,118.571" fill="none"'
        in s,
        "the bar-combo line layer's POST staircase",
    )


def test_render_layers_svg_bar_combo_honors_area_step() raises:
    # The Mark.AREA branch of _render_bar_combo_layers builds its own
    # closed-to-the-baseline geometry too, so mark_area(step=...) has to
    # reach it separately from _draw_area_layer.
    #
    # Same three-category frame as the line-step test above: centers
    # 113.333, 220.000, 326.667, combined_y=[10,20,14,15,5,12]
    # zero-baselines to [0,21] over [250,20], so the area's y=[15,5,12]
    # lands at 85.714, 195.238, 118.571 and the baseline at 250 is
    # pulled to 249 off the axis line.
    #
    # The assertion is the whole `d`, not just the staircase: the two
    # closing segments have to still be there, still straight, and still
    # anchored under the first and last category rather than under a
    # riser. The last riser (326.667, 118.571) and the closing drop to
    # (326.667, 249.000) share an x, which is the staircase and the
    # closing edge meeting with no sliver between them.
    var cats: List[String] = ["A", "B", "C"]
    var bar_y: List[Float64] = [10.0, 20.0, 14.0]
    var idx: List[Float64] = [0.0, 1.0, 2.0]
    var area_y: List[Float64] = [15.0, 5.0, 12.0]
    var bars = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var stepped = (
        Plot()
        .mark_area(step=StepStyle.POST)
        .encode(x=idx, y=area_y)
        .size(400, 300)
    )
    var plots: List[Plot] = [bars^, stepped^]
    var s = render_layers_svg(plots).to_string()
    assert_true(
        '<path d="M113.333,85.714 L220.000,85.714 L220.000,195.238'
        " L326.667,195.238 L326.667,118.571 L326.667,249.000"
        ' L113.333,249.000 Z" fill="#1e64b4"/>'
        in s,
        "the bar-combo area layer's POST staircase, closed to the baseline",
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
    # annotate_band()/annotate_best_fit() weren't part of the
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
    # the bar-combo path (_render_bar_combo_layers) needs the same
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
    # Two cells, 400x300 each, side by side on an 800x300 canvas (cols=2),
    # from each plot's .size(400, 300). Two different mark_colors confirm
    # each cell rendered its own plot rather than one twice.
    #
    # Located by scanning rather than by hand-derived pixel: what
    # this test is about is that each cell drew its own plot in its own
    # half, which the point's position within its cell states directly.
    # The exact center depends on the default margins and the 5% padding,
    # and is anchored by the hand-derived tests that are about geometry.
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

    var left = _bbox_of_color(c, Theme.default().mark_color)
    var right = _bbox_of_color(c, RED)
    assert_true(left.found, "cell 0 drew its point")
    assert_true(right.found, "cell 1 drew its point")

    # Each stays inside its own half, and neither color appears in the
    # other's -- which is what "independent plots side by side" means.
    assert_true(left.x1 < 400, "cell 0's point is in the left half")
    assert_true(right.x0 >= 400, "cell 1's point is in the right half")

    # The same point in the same place within each cell: cell 1 is cell 0
    # shifted by exactly one cell width.
    assert_equal(
        right.center_x() - left.center_x(),
        400,
        "cell 1 is cell 0 shifted one cell width",
    )
    assert_equal(right.center_y(), left.center_y(), "and at the same height")


def test_render_facets_svg_draws_annotate_vline_and_best_fit_in_different_cells() raises:
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
        '<line x1="220.000" y1="20.000" x2="220.000" y2="250.000"'
        ' stroke="#969696" stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        (
            "cell 0's vline, at the same pixel a standalone render of the same"
            " plot would use"
        ),
    )
    assert_true(
        '<line x1="460.000" y1="250.000" x2="780.000" y2="20.000"'
        ' stroke="#969696" stroke-width="1.000" stroke-linecap="round"/>'
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

    # Located per cell rather than by hand-derived pixel: the
    # claim is that three cells drew a point and the fourth was never
    # touched, which is about which cell owns the ink, not where in the
    # cell it landed.
    var mark_color = Theme.default().mark_color
    var top_left = _bbox_of_color_in(c, mark_color, 0, 0, 399, 299)
    var top_right = _bbox_of_color_in(c, mark_color, 400, 0, 799, 299)
    var bottom_left = _bbox_of_color_in(c, mark_color, 0, 300, 399, 599)
    var bottom_right = _bbox_of_color_in(c, mark_color, 400, 300, 799, 599)

    assert_true(top_left.found, "cell (0,0) drew its point")
    assert_true(top_right.found, "cell (0,1) drew its point")
    assert_true(bottom_left.found, "cell (1,0) drew its point")
    assert_true(
        not bottom_right.found,
        "cell (1,1) has no 4th plot, so nothing was drawn there",
    )

    # The three filled cells drew the same plot, so each point sits at the
    # same offset inside its own cell.
    assert_equal(
        top_right.center_x() - top_left.center_x(),
        400,
        "cell (0,1) is cell (0,0) shifted one cell width",
    )
    assert_equal(
        bottom_left.center_y() - top_left.center_y(),
        300,
        "cell (1,0) is cell (0,0) shifted one cell height",
    )

    # The empty cell keeps the canvas's own white default, never painted.
    var blank = _bbox_of_color_in(c, Color(255, 255, 255), 400, 300, 799, 599)
    assert_true(blank.found, "cell (1,1) is still the untouched background")


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
        '<circle cx="220.000" cy="135.000" r="4.000" fill="#1e64b4"/>' in s,
        "cell 0's point, same coordinates render_facets()'s test finds",
    )
    assert_true(
        '<circle cx="620.000" cy="135.000" r="4.000" fill="#ff0000"/>' in s,
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
        '<circle cx="220.000" cy="146.000" r="4.000" fill="#1e64b4"/>' in s,
        "cell 0's point, shifted down to make room for its title",
    )
    assert_true(
        '<circle cx="620.000" cy="135.000" r="4.000" fill="#ff0000"/>' in s,
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
        'cy="239.545"' in s,
        "cell 0's own point (y=10) lands at the hand-derived shared-scale row",
    )
    assert_true(
        'cy="30.455"' in s,
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


def _occurrences(s: String, sub: String) -> Int:
    var n = 0
    var at = s.find(sub)
    while at >= 0:
        n += 1
        at = s.find(sub, at + 1)
    return n


def test_render_facets_shared_y_scale_puts_one_value_on_one_row_across_area_cells() raises:
    # Two Mark.AREA cells, 400x300 each (rows=1, default theme ->
    # plot_y0=20, plot_y1=250): y0=[5, 20] and y1=[20, 70]. An AREA cell
    # forces the zero baseline on the shared domain (#442): [0, 70],
    # padded 5% at the top only -> [0, 73.5].
    #
    # scale() = (20-250)/73.5 = -3.1293
    # to_pixel(20) = 250 - 62.585 = 187.415
    # to_pixel(70) = 250 - 219.048 = 30.952
    #
    # Scaled to itself, cell 0's domain would be [0, 21] and its 20 would
    # land at 30.952 -- the row every cell's own maximum lands on. So
    # 187.415 appearing in both cells is the shared scale at work, and
    # 30.952 appearing exactly once is cell 0 no longer scaled to itself.
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 20.0]
    var y1: List[Float64] = [20.0, 70.0]
    var p0 = Plot().size(400, 300).mark_area().encode(x=x, y=y0)
    var p1 = Plot().size(400, 300).mark_area().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    var s = render_facets_svg(plots, 2, shared_y_scale=True).to_string()
    assert_equal(_occurrences(s, "187.415"), 2)
    assert_equal(_occurrences(s, "30.952"), 1)


def test_render_facets_svg_shared_y_scale_supports_log_when_every_cell_agrees() raises:
    # two log-y cells, y0=[5,6] and y1=[50,60]. Verified by
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
        var idx = s.find('cy="135.000"', search_from)
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
    # tick at (350, 135). Sampled at x=350: since the supersampling
    # rewrite the tick lands fully opaque across x=350..354 rather than on
    # whichever single column the old device-space rounding happened to
    # fill, so this no longer depends on picking the lucky one.
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
        350,
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


def _scattered_samples() raises -> List[List[Float64]]:
    """80 pseudo-random `(x, y, z)` samples, the shape
    `encode_tricontour()` takes. The generator is the LCG every
    tricontour example uses, so the samples are the same ones the docs
    render.
    """
    var x = List[Float64]()
    var y = List[Float64]()
    var z = List[Float64]()
    var seed = 12345
    for _ in range(80):
        seed = (seed * 1103515245 + 12345) % 2147483648
        var px = Float64(seed % 1000) / 100.0
        seed = (seed * 1103515245 + 12345) % 2147483648
        var py = Float64(seed % 1000) / 100.0
        x.append(px)
        y.append(py)
        z.append(sin(px) * cos(py))
    var out = List[List[Float64]]()
    out.append(x^)
    out.append(y^)
    out.append(z^)
    return out^


def test_render_layers_names_the_rejected_layer_and_where_the_gap_is_tracked() raises:
    """Name the rejected layer index and mark in the diagnostic."""
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var lx: List[Float64] = [0.0, 10.0]
    var ly: List[Float64] = [0.0, 10.0]
    var plots = List[Plot]()
    plots.append(line(lx, ly, width=400, height=300))
    plots.append(
        Plot().mark_arc().encode_categorical(x=cats, y=vals).size(400, 300)
    )
    with assert_raises(contains="layer 1"):
        _ = render_layers(plots)
    with assert_raises(contains="Mark.ARC"):
        _ = render_layers(plots)
    with assert_raises(contains="render_facets()"):
        _ = render_layers(plots)

    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var sizes: List[Float64] = [0.0, 3.0, 2.0]
    var hier = List[Plot]()
    hier.append(line(lx, ly, width=400, height=300))
    hier.append(
        Plot()
        .mark_treemap()
        .encode_hierarchy(ids=ids, parent_ids=parents, values=sizes)
        .size(400, 300)
    )
    with assert_raises(contains="Mark.TREEMAP"):
        _ = render_layers(hier)


def test_layering_a_tricontour_over_a_tricontourf_draws_both() raises:
    """The exact call `tricontourf()`'s docstring recommends,
    which raised until the allow-list opened.

    The discriminating assertion is not "it drew something": it is that
    **every one of the standalone `tricontour()`'s 36 `<path>` elements
    appears verbatim in the combined render**. A `<path>`'s `d` is the
    whole polyline in absolute pixel coordinates, so matching it is
    matching every vertex -- if the combined x/y domain were not the
    same one the standalone computed, the isolines would land on
    different pixels and no path would match. That is exactly what 's
    testing plan asked for, and it is what a loose "the SVG contains a
    `<path>`" assertion would miss.

    It holds because both layers contribute the same x/y columns to the
    combined domain, and `_data_extent` of a column unioned with itself
    is that column's extent.
    """
    var s = _scattered_samples()
    var plots = List[Plot]()
    plots.append(tricontourf(s[0], s[1], s[2], width=400, height=300))
    plots.append(tricontour(s[0], s[1], s[2], width=400, height=300))
    var combo = render_layers_svg(plots).to_string()
    var solo = render_svg(
        tricontour(s[0], s[1], s[2], width=400, height=300)
    ).to_string()

    var solo_paths = _elements_of(solo, "<path")
    assert_equal(
        len(solo_paths), 36, "the standalone tricontour draws 36 isoline paths"
    )
    for i in range(len(solo_paths)):
        assert_true(
            combo.find(solo_paths[i]) >= 0,
            (
                "isoline path "
                + String(i)
                + " lands on the same pixels in the combined render"
            ),
        )
    assert_true(
        len(_elements_of(combo, "<path")) > len(solo_paths),
        "the filled bands are drawn as well, not only the isolines",
    )


def test_layering_two_kde_curves_puts_both_on_one_shared_density_axis() raises:
    """Seaborn compares distributions by calling `kdeplot()`
    twice onto one axes. This is that call, which raised until the
    allow-list opened.

    Two curves is the easy half. The discriminating half is the shared
    y-domain: `b` here is a tight cluster, so its density peaks far
    higher than `a`'s, and on one frame `a`'s curve must be **squashed**
    relative to its standalone render -- same x pixels (a's own spread
    still sets the x-domain), lower on the page.

    "It rendered without raising" would pass even if each layer had been
    drawn against its own y-domain, which is the bug worth catching: a
    stack where every curve peaks at the same height is a stack that
    says nothing about their relative densities. Comparing the first
    vertex's y against the standalone's is what discriminates, and the
    expected value comes from a *different* function (`render_svg` of
    one layer), never from `render_layers` itself.
    """
    var a: List[Float64] = [1.0, 2.0, 2.5, 3.0, 4.0, 4.5, 5.0]
    var b: List[Float64] = [3.0, 3.05, 3.1, 3.0, 3.02, 3.08, 3.01]
    var plots = List[Plot]()
    plots.append(kdeplot(a, width=400, height=300))
    plots.append(kdeplot(b, width=400, height=300))
    var combo = render_layers_svg(plots).to_string()

    var combo_paths = _elements_of(combo, "<path")
    assert_equal(len(combo_paths), 2, "both density curves are drawn")

    var solo = render_svg(kdeplot(a, width=400, height=300)).to_string()
    var solo_paths = _elements_of(solo, "<path")
    var solo_first = _first_vertex(solo_paths[0])
    var combo_first = _first_vertex(combo_paths[0])
    assert_equal(
        combo_first[0],
        solo_first[0],
        "a's curve starts at the same x -- its own spread sets the x-domain",
    )
    assert_true(
        combo_first[1] > solo_first[1] + 0.5,
        (
            "a's curve is pushed down the page by b's much taller peak"
            " sharing the y-domain (standalone y "
            + String(solo_first[1])
            + ", layered y "
            + String(combo_first[1])
            + ")"
        ),
    )
    assert_true(
        combo_first[1] < 250.0,
        "and it is still inside the plot rect, not clipped off the bottom",
    )


def test_tricontour_and_tricontourf_draw_the_same_axis_frame() raises:
    """Both contour variants produce identical frames for the same x/y.

    Asserted on the SVG rather than on pixels because the frame is
    exactly the elements SVG names: every `<line>` (the two axis lines
    and the gridlines) and every `<text>` (the tick labels), compared
    element by element. A raster comparison would be dominated by the
    contours themselves, which are supposed to differ.

    """
    var s = _scattered_samples()
    var a = render_svg(
        tricontour(s[0], s[1], s[2], width=400, height=300)
    ).to_string()
    var b = render_svg(
        tricontourf(s[0], s[1], s[2], width=400, height=300)
    ).to_string()

    var lines_a = _elements_of(a, "<line")
    var lines_b = _elements_of(b, "<line")
    assert_true(
        len(lines_a) > 0, "the frame draws axis lines and gridlines at all"
    )
    assert_equal(
        len(lines_a),
        len(lines_b),
        "both marks draw the same number of frame lines",
    )
    for i in range(len(lines_a)):
        assert_equal(
            lines_a[i],
            lines_b[i],
            "frame line " + String(i) + " is identical across the two marks",
        )

    var text_a = _elements_of(a, "<text")
    var text_b = _elements_of(b, "<text")
    assert_true(len(text_a) > 0, "the frame draws tick labels at all")
    assert_equal(
        len(text_a),
        len(text_b),
        "both marks draw the same number of tick labels",
    )
    for i in range(len(text_a)):
        assert_equal(
            text_a[i],
            text_b[i],
            "tick label " + String(i) + " is identical across the two marks",
        )


def _elements_of(svg: String, tag: String) -> List[String]:
    """Every element opening with `tag`, from `<` to the matching `>`,
    in document order. Enough to compare frame geometry: the axis lines
    and tick labels this reads carry no child content.
    """
    var out = List[String]()
    var i = svg.find(tag)
    while i >= 0:
        var j = svg.find(">", i)
        out.append(String(svg[byte = i : j + 1]))
        i = svg.find(tag, j)
    return out^


def _first_vertex(path_element: String) raises -> List[Float64]:
    """The `M x,y` a `<path d="...">` element opens with, as `[x, y]`.

    Enough to pin where a curve starts without pinning the whole
    polyline, which is what the shared-domain tests need: a domain error
    moves the first vertex as much as any other.
    """
    var k = path_element.find('d="M')
    var comma = path_element.find(",", k)
    var space = path_element.find(" ", comma)
    var out = List[Float64]()
    out.append(Float64(String(path_element[byte = k + 4 : comma])))
    out.append(Float64(String(path_element[byte = comma + 1 : space])))
    return out^


def _attr(element: String, name: String) raises -> String:
    """One attribute's value out of an SVG element string."""
    var k = element.find(name + '="')
    if k < 0:
        raise Error("no " + name + ' attribute in "' + element + '"')
    var start = k + name.byte_length() + 2
    return String(element[byte = start : element.find('"', start)])


def _path_baseline_y(path_element: String) raises -> Float64:
    """The largest y coordinate in a `<path d="...">`'s vertex list.

    For a filled `Mark.KDE` that is the baseline the fill closes down
    to, which is where the y-domain's zero landed -- the one number that
    separates `_zero_baseline_y_extent` from `_data_extent` for a
    strictly positive density column.
    """
    var d = _attr(path_element, "d")
    var best = -1.0
    var i = 0
    while True:
        var comma = d.find(",", i)
        if comma < 0:
            break
        var space = d.find(" ", comma)
        var end = space if space >= 0 else d.byte_length()
        var y = Float64(String(d[byte = comma + 1 : end]))
        if y > best:
            best = y
        i = end
    return best


def _x_axis_row(svg: String) raises -> Float64:
    """The y of the plot rect's bottom edge, read off the x-axis line --
    the lowest horizontal `<line>` drawn in `Theme.axis_color`.

    Read rather than hard-coded so the tests that use it assert a
    *relationship* (the fill closes on the axis) instead of a pair of
    independent golden numbers that could both drift together.
    """
    var best = -1.0
    var lines = _elements_of(svg, "<line")
    for i in range(len(lines)):
        if lines[i].find('stroke="#505050"') < 0:
            continue
        var y1 = Float64(_attr(lines[i], "y1"))
        if y1 != Float64(_attr(lines[i], "y2")):
            continue  # a vertical line: the y-axis, or a tick
        if y1 > best:
            best = y1
    return best


def _lone_layer_matches_standalone(
    name: String, var plot: Plot, solo: String
) raises:
    """`render_layers_svg([plot])` produces byte-identical output to
    `render_svg()` of the same plot.

    The strongest domain-correctness assertion available for a newly
    layerable mark, and the one this module leans on for all eight of
    them. A stack of one has exactly one layer's data in the
    combined domain, so the frame, the scales and every drawn coordinate
    must come out the same as the standalone render's -- if the layered
    path read the wrong field for a mark's x/y, applied the wrong extent
    helper (`_data_extent` vs `_zero_baseline_y_extent`), or handed a
    layer a scale ranged against something else, the strings diverge.

    "It rendered without raising" is what this replaces, and it would
    pass for every one of those bugs.
    """
    var plots = List[Plot]()
    plots.append(plot^)
    var layered = render_layers_svg(plots).to_string()
    assert_true(
        layered.byte_length() > 0, name + ": the layered render is not empty"
    )
    assert_equal(
        layered,
        solo,
        name + ": a stack of one draws exactly the standalone chart",
    )


def test_a_lone_kde_layer_draws_the_standalone_kde() raises:
    """. See `_lone_layer_matches_standalone`.

    `Mark.KDE` is the mark this is most likely to catch: its standalone
    y-domain is `LinearScale(0.0, y_max * 1.05)`, written by hand rather
    than through either shared extent helper. It matches
    `_zero_baseline_y_extent` over the density column exactly (lo is
    `min(0, min density)` = 0, hi is padded 5%), which is why the layered
    path can use the shared helper and still land here -- and this
    assertion is what would fail if that reasoning were wrong, or if
    `_data_extent` had been used instead and padded the axis below zero.
    """
    var v: List[Float64] = [12.0, 14.0, 15.0, 16.0, 17.0, 24.0, 25.0, 28.0]
    _lone_layer_matches_standalone(
        "Mark.KDE",
        kdeplot(v, width=400, height=300),
        render_svg(kdeplot(v, width=400, height=300)).to_string(),
    )


def test_a_lone_rug_layer_draws_the_standalone_rug_including_no_y_axis() raises:
    """A stack of nothing but
    `Mark.RUG` layers has no host y-axis, so it falls back to the
    standalone treatment -- the `LinearScale(0, 1)` placeholder with the
    y half suppressed, rather than publishing "0.0 0.2 ... 1.0" as a
    density that isn't there.

    Byte equality covers that: a layered render that drew the y-axis
    would have four more `<text>` elements and a different left margin.
    """
    var v: List[Float64] = [12.0, 14.0, 15.0, 16.0, 17.0, 24.0, 25.0, 28.0]
    _lone_layer_matches_standalone(
        "Mark.RUG",
        rugplot(v, width=400, height=300),
        render_svg(rugplot(v, width=400, height=300)).to_string(),
    )


def test_a_lone_layer_of_each_field_mark_draws_the_standalone_chart() raises:
    """For the five remaining newly-layerable marks, each through
    `_lone_layer_matches_standalone`.

    `Mark.BARBS`, `TRICONTOUR`, `TRICONTOURF`, `TRIPLOT` and `TRIPCOLOR`
    all keep their x/y in a field of their own (`_barbs`, `_tricontour`,
    `_triplot`) rather than in `Plot.encode()`'s `x_data`/`y_data`, so
    "the layered path read the wrong column" is a live failure mode for
    each and byte equality is what rules it out.
    """
    var s = _scattered_samples()
    var bx: List[Float64] = [0.0, 1.0, 2.0, 0.0, 1.0, 2.0]
    var by: List[Float64] = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
    var bu: List[Float64] = [5.0, 12.0, 27.0, 55.0, 0.0, 33.0]
    var bv: List[Float64] = [3.0, -8.0, 14.0, 2.0, 0.0, -20.0]

    _lone_layer_matches_standalone(
        "Mark.BARBS",
        barbs(bx, by, bu, bv, width=400, height=300),
        render_svg(barbs(bx, by, bu, bv, width=400, height=300)).to_string(),
    )
    _lone_layer_matches_standalone(
        "Mark.TRICONTOUR",
        tricontour(s[0], s[1], s[2], width=400, height=300),
        render_svg(
            tricontour(s[0], s[1], s[2], width=400, height=300)
        ).to_string(),
    )
    _lone_layer_matches_standalone(
        "Mark.TRICONTOURF",
        tricontourf(s[0], s[1], s[2], width=400, height=300),
        render_svg(
            tricontourf(s[0], s[1], s[2], width=400, height=300)
        ).to_string(),
    )
    _lone_layer_matches_standalone(
        "Mark.TRIPLOT",
        triplot(s[0], s[1], width=400, height=300),
        render_svg(triplot(s[0], s[1], width=400, height=300)).to_string(),
    )
    _lone_layer_matches_standalone(
        "Mark.TRIPCOLOR",
        tripcolor(s[0], s[1], s[2], width=400, height=300),
        render_svg(
            tripcolor(s[0], s[1], s[2], width=400, height=300)
        ).to_string(),
    )


def test_a_lone_effect_scatter_layer_draws_its_halo() raises:
    """Admitted `Mark.EFFECT_SCATTER` alongside `Mark.POINT`, which
    it shares `_draw_point_layer` with.

    Byte equality is the assertion, and the halo is what makes it
    discriminating here: an `EFFECT_SCATTER` layer dispatched as a plain
    `Mark.POINT` (`draw_halo=False`, the easy mistake given the shared
    draw function) would still render a perfectly reasonable scatter,
    with exactly half the `<circle>` elements. The count is asserted
    separately so a failure says which half went wrong.
    """
    var ex: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var ey: List[Float64] = [1.0, 3.0, 2.0, 4.0]
    var solo = render_svg(
        effect_scatter(ex, ey, width=400, height=300)
    ).to_string()
    assert_equal(
        len(_elements_of(solo, "<circle")),
        8,
        "four points, each a halo plus a marker",
    )
    _lone_layer_matches_standalone(
        "Mark.EFFECT_SCATTER",
        effect_scatter(ex, ey, width=400, height=300),
        solo,
    )


def test_layering_a_rug_under_a_kde_draws_what_kdeplot_rug_true_draws() raises:
    """Verify the layered composition: `render_layers([kdeplot(v), rugplot(v)])` is
    **byte-identical** to `render(kdeplot(v, rug=True))`.

    `mark_kde(rug=True)` is the built-in alternative. The composed
    chart has to be the same chart -- so this pins the two paths
    together, and any future divergence in either shows up here.

    It is not a tautology. The frames agree only because the combined
    x-domain works out to the KDE's own: the curve runs three bandwidths
    past the observations on each side, so the rug layer's raw values
    are strictly inside it and the union's `_data_extent` is the curve's.
    The rug ticks then have to land on the *curve's* x-scale, not on the
    scale a standalone `rugplot()` would have built from the raw values
    -- which is a visibly different chart, and what byte equality here
    rules out.
    """
    var v: List[Float64] = [12.0, 14.0, 15.0, 15.0, 16.0, 17.0, 24.0, 28.0]
    var plots = List[Plot]()
    plots.append(kdeplot(v, width=400, height=300))
    plots.append(rugplot(v, width=400, height=300))
    var layered = render_layers_svg(plots).to_string()
    var built_in = render_svg(
        kdeplot(v, rug=True, width=400, height=300)
    ).to_string()
    assert_equal(
        len(_elements_of(built_in, "<line"))
        - len(_elements_of(layered, "<line")),
        0,
        "the same number of rug ticks and frame lines",
    )
    assert_equal(
        layered,
        built_in,
        "layering a rug under a kde draws exactly kdeplot(rug=True)",
    )


def test_a_rug_layer_rides_the_shared_x_domain_not_its_own() raises:
    """The domain-correctness check that a lone-layer comparison cannot
    make: what happens when the layers *disagree* about the x extent.

    The rug's observations here span far wider than the KDE's, so the
    combined x-domain is the rug's and the density curve has to be
    compressed into the middle of the frame. Asserted by comparing the
    curve's first vertex against its own standalone render -- it must
    move right, because the frame now starts well to the left of where
    the curve does.

    A layered path that drew each mark against its own x-scale would
    produce a chart that looks fine and is a lie; this is what catches
    it. The expected value comes from `render_svg` of the KDE alone,
    never from `render_layers`.
    """
    var v: List[Float64] = [1.0, 2.0, 2.5, 3.0, 4.0, 4.5, 5.0]
    var wide: List[Float64] = [-20.0, 40.0]
    var plots = List[Plot]()
    plots.append(kdeplot(v, width=400, height=300))
    plots.append(rugplot(wide, width=400, height=300))
    var layered = render_layers_svg(plots).to_string()

    var solo_x = _first_vertex(
        _elements_of(
            render_svg(kdeplot(v, width=400, height=300)).to_string(), "<path"
        )[0]
    )[0]
    var layered_x = _first_vertex(_elements_of(layered, "<path")[0])[0]
    assert_true(
        layered_x > solo_x + 50.0,
        (
            "the curve is pushed right into the middle of the wider shared"
            " x-domain (standalone x "
            + String(solo_x)
            + ", layered x "
            + String(layered_x)
            + ")"
        ),
    )
    # 2 rug ticks on top of the frame's own lines, and the y-axis is
    # still drawn: the KDE layer supplies a real density domain, so the
    # all-rug suppression must not fire here.
    assert_true(
        len(_elements_of(layered, "<text")) > 4,
        "the y-axis tick labels are still drawn: the KDE layer owns them",
    )


def test_a_kde_layer_anchors_a_shared_domain_at_zero() raises:
    """The extent-helper divergence  had to reconcile: `Mark.KDE`
    anchors its y at zero (`_zero_baseline_y_extent`, like `Mark.AREA`)
    while `Mark.POINT` pads around its data (`_data_extent`). One shared
    axis has to pick, and a density's zero is not negotiable -- a filled
    curve floating above the baseline is a chart claiming the
    distribution has a floor it doesn't.

    The layers here are chosen so the two rules give *different*
    answers, which most pairings do not: the scatter's y all sit well
    above the density peak, so `_data_extent` over the union would take
    its lower end from the curve's smallest density (a hair above zero)
    and then pad 5% *below* it, putting the domain minimum at a negative
    density and the baseline several pixels up from the axis line.
    `_zero_baseline_y_extent` pins the minimum at exactly zero.

    Two assertions discriminate: the filled curve closes at exactly the
    plot rect's bottom edge -- read from the x-axis `<line>`, not
    hard-coded -- and the lowest y tick label is at that same row. A
    layered path that used `_data_extent` here draws a perfectly
    plausible chart and fails both. (Deliberately *not* asserted with a
    negative-y co-layer: when the data straddles zero the two helpers
    agree exactly, so such a case cannot discriminate at all.)
    """
    var v: List[Float64] = [1.0, 2.0, 2.5, 3.0, 4.0, 4.5, 5.0]
    var sx: List[Float64] = [2.0, 3.0]
    var sy: List[Float64] = [5.0, 6.0]
    var plots = List[Plot]()
    plots.append(kdeplot(v, fill=True, width=400, height=300))
    plots.append(scatter(sx, sy, width=400, height=300))
    var layered = render_layers_svg(plots).to_string()

    var axis_y = _x_axis_row(layered)
    assert_true(
        axis_y > 200.0,
        "sanity: the x-axis sits near the bottom of a 300px canvas",
    )
    var paths = _elements_of(layered, "<path")
    # The fill and the stroke are separate paths (the stroke must not
    # carry the two closing segments, or the baseline reads as an axis);
    # the fill is drawn first.
    assert_equal(len(paths), 2, "one density curve, filled and stroked")
    assert_equal(
        _path_baseline_y(paths[0]),
        axis_y,
        "the fill closes on the axis line: zero is the domain's exact minimum",
    )

    var labels = _elements_of(layered, "<text")
    var lowest_y_label_row = -1.0
    for i in range(len(labels)):
        if labels[i].find('text-anchor="end"') < 0:
            continue  # an x-axis label, not a y one
        var row = Float64(_attr(labels[i], "y"))
        if row > lowest_y_label_row:
            lowest_y_label_row = row
    # Tick labels are baseline-anchored, so the "0" label's own y sits a
    # few px below the tick it captions rather than exactly on it.
    assert_true(
        lowest_y_label_row > axis_y and lowest_y_label_row < axis_y + 8.0,
        (
            "the bottom y tick is the axis line itself (axis row "
            + String(axis_y)
            + ", lowest label row "
            + String(lowest_y_label_row)
            + ")"
        ),
    )
    assert_equal(
        len(_elements_of(layered, "<circle")),
        2,
        "and both scatter points are still drawn",
    )


def test_render_layers_rejects_a_log_scale_on_a_newly_layerable_mark() raises:
    """Admitted eight marks whose domains are only ever taken
    linearly. `_render_generic` already refuses `scale_x_log()`/
    `scale_y_log()` on anything but `Mark.POINT`/`LINE`/`AREA`/
    `EFFECT_SCATTER`; the layered path has to refuse it too, or a KDE
    beside a log-scaled line would be drawn against a log axis it was
    never mapped through.

    `contains="layer 1"` discriminates: the offending layer is the
    second, so a message naming a constant index would not match.
    """
    var lx: List[Float64] = [1.0, 10.0]
    var ly: List[Float64] = [1.0, 10.0]
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var plots = List[Plot]()
    plots.append(line(lx, ly, width=400, height=300).scale_y_log())
    plots.append(kdeplot(v, width=400, height=300).scale_y_log())
    with assert_raises(contains="layer 1"):
        _ = render_layers(plots)
    with assert_raises(contains="scale_y_log"):
        _ = render_layers(plots)


def test_render_layers_rejects_secondary_axis_on_a_rug_layer() raises:
    """A `Mark.RUG` layer contributes no y values at all, so
    `.secondary_axis()` on one would leave the secondary domain empty and
    the right-hand axis silently undrawn -- a builder call that does
    nothing, which is worse than one that refuses.

    Discriminating on `contains="layer 1"` again: the rug is the second
    layer.
    """
    var lx: List[Float64] = [1.0, 10.0]
    var ly: List[Float64] = [1.0, 10.0]
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var plots = List[Plot]()
    plots.append(line(lx, ly, width=400, height=300))
    plots.append(rugplot(v, width=400, height=300).secondary_axis())
    with assert_raises(contains="layer 1"):
        _ = render_layers(plots)
    with assert_raises(contains="secondary_axis"):
        _ = render_layers(plots)


def test_an_annotation_on_an_empty_secondary_layer_raises_instead_of_drawing() raises:
    """A `_RenderResult`'s `has_y_scale` is what tells
    `annotate_line()`/`annotate_area()` there is a real y-domain to place
    themselves against. The layered path hard-coded it to `True`
    for every layer, which is wrong for a `.secondary_axis()` layer that
    contributed nothing to the secondary domain: the right-hand axis is
    then never drawn, `y_scale2` stays the degenerate
    `LinearScale(0.0, 0.0, ...)` placeholder, and an `annotate_line()`
    against it is placed against nothing.

    The layer must raise instead of placing an annotation against the
    degenerate placeholder scale.
    """
    var lx: List[Float64] = [0.0, 10.0]
    var ly: List[Float64] = [0.0, 10.0]
    var empty = List[Float64]()
    var plots = List[Plot]()
    plots.append(line(lx, ly, width=400, height=300))
    plots.append(
        scatter(empty, empty, width=400, height=300)
        .secondary_axis()
        .annotate_line(5.0, label="target")
    )
    with assert_raises(contains="no continuous y-axis"):
        _ = render_layers(plots)


def test_render_layers_still_rejects_a_contour_layer_and_says_why() raises:
    """`Mark.CONTOUR`/`CONTOURF` draw through the same
    `_draw_continuous_axis_frame` as everything  admitted, and are
    still refused -- their axes are unpadded *grid-index* units, not the
    caller's coordinates, so sharing an x with a coordinate mark would
    equate column 12 with the value 12.

    The error must explain the incompatible coordinate system.
    """
    var z = List[List[Float64]]()
    var row0: List[Float64] = [0.0, 1.0, 2.0]
    var row1: List[Float64] = [1.0, 3.0, 1.0]
    var row2: List[Float64] = [2.0, 1.0, 0.0]
    z.append(row0^)
    z.append(row1^)
    z.append(row2^)
    var lx: List[Float64] = [0.0, 2.0]
    var ly: List[Float64] = [0.0, 2.0]
    var plots = List[Plot]()
    plots.append(line(lx, ly, width=400, height=300))
    plots.append(contour(z, width=400, height=300))
    with assert_raises(contains="layer 1"):
        _ = render_layers(plots)
    with assert_raises(contains="grid-index units"):
        _ = render_layers(plots)


# ---------------------------------------------------------------
# Facet row spacing
# ---------------------------------------------------------------


def _titled_facet_grid(x_title: String) raises -> List[Plot]:
    """Four 320x240 cells, each with a chart title and optionally an
    x-axis title -- the combination whose ink used to collide across the
    row boundary."""
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [12.0, 19.0, 14.0, 25.0, 18.0]
    var names: List[String] = ["PRE", "MID", "POST", "NONE"]
    var plots = List[Plot]()
    for i in range(4):
        plots.append(
            Plot()
            .size(320, 240)
            .mark_line()
            .encode(x=x, y=y)
            .labels(title=names[i], x_title=x_title, y_title="Rate (%)")
            .theme(Theme(show_gridlines=False))
        )
    return plots^


def _clear_rows_between(c: Canvas, y0: Int, y1: Int, x0: Int, x1: Int) -> Int:
    """The longest run of ink-free rows lying *between* the first and
    last inked rows of `[y0, y1)`, scanning columns `x0` to `x1`.

    Bounded by the ink deliberately. Measuring the longest clear run
    anywhere in the window answers a different question -- it finds the
    empty space *above* the first text block, which was 26 rows here and
    made the first version of this test pass with and without the fix.
    """
    var inked = List[Bool](capacity=y1 - y0)
    var first = -1
    var last = -1
    for y in range(y0, y1):
        var has_ink = False
        for x in range(x0, x1):
            var p = c.get_pixel(x, y)
            if p.r != 255 or p.g != 255 or p.b != 255:
                has_ink = True
                break
        inked.append(has_ink)
        if has_ink:
            if first < 0:
                first = y
            last = y
    if first < 0 or last <= first:
        return 0

    var best = 0
    var run = 0
    for y in range(first, last + 1):
        if inked[y - y0]:
            run = 0
        else:
            run += 1
            if run > best:
                best = run
    return best


def test_facet_rows_leave_a_gap_between_an_x_title_and_the_next_title() raises:
    """Cells tile edge to edge, so a cell's x-axis title landed
    directly against the next row's chart title.

    On a 2x2 grid of 320x240 cells this was not merely tight: scanning
    rows 200-274 between columns 40 and 300, the longest ink-free run
    *between* the two blocks is **0** without the gutter -- they touch --
    against 8 with it.

    Six is asserted rather than eight so an unrelated font or metric
    change does not relitigate this; zero is what it has to stay away
    from.
    """
    var c = render_facets(_titled_facet_grid("Meeting"), 2)
    assert_true(
        _clear_rows_between(c, 200, 275, 40, 300) >= 6,
        (
            "a facet row's x-axis title needs clear space before the next"
            " row's title -- longest clear run was "
            + String(_clear_rows_between(c, 200, 275, 40, 300))
        ),
    )


def test_a_facet_grid_without_x_titles_is_unchanged() raises:
    """The gutter is charged only to a grid that has the collision. With
    no x-axis title there is nothing to separate, so the layout must be
    exactly what it was -- this is the compatibility half, and it is why
    the gutter is conditional rather than always-on.

    Asserted against a hand-built grid at the same size rather than
    against a golden, so it says "identical to a grid that never asked
    for a gutter" rather than "identical to whatever was recorded".
    """
    var without = render_facets_svg(_titled_facet_grid(""), 2).to_string()
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [12.0, 19.0, 14.0, 25.0, 18.0]
    var names: List[String] = ["PRE", "MID", "POST", "NONE"]
    var reference = List[Plot]()
    for i in range(4):
        reference.append(
            Plot()
            .size(320, 240)
            .mark_line()
            .encode(x=x, y=y)
            .labels(title=names[i], y_title="Rate (%)")
            .theme(Theme(show_gridlines=False))
        )
    assert_equal(
        without,
        render_facets_svg(reference^, 2).to_string(),
        "a grid with no x-axis titles pays no gutter",
    )


# ---------------------------------------------------------------
# The bar-combo path draws through the shared functions (#422)
# ---------------------------------------------------------------


def _title_count(svg: String) -> Int:
    var n = 0
    var at = svg.find("<title>")
    while at >= 0:
        n += 1
        at = svg.find("<title>", at + 1)
    return n


def test_bar_combo_point_layer_emits_its_own_tooltips() raises:
    """#422: `_render_bar_combo_layers` drew its `Mark.POINT` layer with
    a bare `fill_circle_aa`, so `mark_point(tooltips=True)` produced no
    `<title>` at all -- the third styling feature this path dropped by
    reimplementing geometry the shared functions already had.

    The expected count is **derived from the point layer**, not a fixed
    number: bars alone, plus one per point. A fix that emitted groups
    for the bars only, or that hard-coded three, still fails this.
    """
    var cats: List[String] = ["A", "B", "C"]
    var bar_y: List[Float64] = [10.0, 20.0, 15.0]
    var idx: List[Float64] = [0.0, 1.0, 2.0]
    var pt_y: List[Float64] = [12.0, 18.0, 14.0]
    var t = Theme(svg_tooltips=True, show_gridlines=False)

    var bars_only = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(t)
        .size(400, 300)
    )
    var solo: List[Plot] = [bars_only^]
    var bars_alone = _title_count(render_layers_svg(solo).to_string())

    var b2 = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(t)
        .size(400, 300)
    )
    var p2 = (
        Plot()
        .mark_point(tooltips=True)
        .encode(x=idx, y=pt_y)
        .theme(t)
        .size(400, 300)
    )
    var combo: List[Plot] = [b2^, p2^]
    var with_points = _title_count(render_layers_svg(combo).to_string())

    assert_equal(
        with_points,
        bars_alone + len(pt_y),
        (
            "a bar-combo point layer contributes one <title> per point --"
            " bars alone gave "
            + String(bars_alone)
            + ", the combo gave "
            + String(with_points)
        ),
    )


def _line_path_without_coords(svg: String) raises -> String:
    """The stroked `<path>` element with its `d="..."` removed, so two
    renders can be compared on styling alone when their x positions
    differ."""
    var at = svg.find('<path d="M')
    var end = svg.find("/>", at)
    var el = String(svg[byte = at : end + 2])
    var ds = el.find(' d="')
    var de = el.find('"', ds + 4)
    return String(el[byte=0:ds]) + String(el[byte = de + 1 : el.byte_length()])


def test_bar_combo_line_layer_is_styled_like_a_standalone_line() raises:
    """The guard against a fourth dropped feature.

    Every attribute of the stroked path except its coordinates must
    match a standalone line's: stroke, width, dash pattern, linecap.
    The x positions differ -- categorical band centers against a
    continuous scale -- so `d` is the one thing excluded.

    This is future-proof in a way the previous three fixes were not.
    They each repeated one argument in the second copy; the bar-combo
    path now *calls* `_draw_line_layer`, so an argument added there
    appears in both renders or this fails.
    """
    var cats: List[String] = ["A", "B", "C"]
    var bar_y: List[Float64] = [10.0, 20.0, 15.0]
    var idx: List[Float64] = [0.0, 1.0, 2.0]
    var line_y: List[Float64] = [12.0, 18.0, 14.0]
    var t = Theme(show_gridlines=False, show_legend=False)

    var standalone = (
        Plot()
        .mark_line(style=LineStyle.DASHED, step=StepStyle.POST)
        .encode(x=idx, y=line_y)
        .theme(t)
        .size(400, 300)
    )
    var solo_svg = render_svg(standalone).to_string()

    var b = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=bar_y)
        .theme(t)
        .size(400, 300)
    )
    var l = (
        Plot()
        .mark_line(style=LineStyle.DASHED, step=StepStyle.POST)
        .encode(x=idx, y=line_y)
        .theme(t)
        .size(400, 300)
    )
    var combo: List[Plot] = [b^, l^]
    var combo_svg = render_layers_svg(combo).to_string()

    assert_equal(
        _line_path_without_coords(combo_svg),
        _line_path_without_coords(solo_svg),
        "a bar-combo line is styled exactly as the same line standalone",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


def test_render_layers_takes_two_ecdfs_and_pins_the_proportion_axis() raises:
    """Two ECDFs on one frame -- the comparison that is the main reason to
    draw one (#440). `a` is stochastically below `b` up to 4 and above it
    after, so the two staircases cross exactly once; that is asserted on
    the curves' own vertices, and the render is checked for one stroked
    path per layer and a y-axis pinned to `[0, 1]` rather than padded.
    """
    var a: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    var b: List[Float64] = [0.5, 0.6, 0.7, 7.0, 8.0, 9.0]
    var fa = _ecdf_points(a)
    var fb = _ecdf_points(b)

    # Walk both curves over the sorted union of x; count sign changes of
    # F_a - F_b. Sorted, or the walk sees the two samples one after the
    # other and counts every return trip as a crossing.
    var xs = List[Float64]()
    for v in a:
        xs.append(v)
    for v in b:
        xs.append(v)
    for i in range(1, len(xs)):
        var k = i
        while k > 0 and xs[k] < xs[k - 1]:
            var tmp = xs[k]
            xs[k] = xs[k - 1]
            xs[k - 1] = tmp
            k -= 1
    var changes = 0
    var prev = 0
    for x in xs:
        var ya = 0.0
        for i in range(len(fa.x)):
            if fa.x[i] <= x:
                ya = fa.y[i]
        var yb = 0.0
        for i in range(len(fb.x)):
            if fb.x[i] <= x:
                yb = fb.y[i]
        var sign = 1 if ya > yb else (-1 if ya < yb else 0)
        if sign != 0 and prev != 0 and sign != prev:
            changes += 1
        if sign != 0:
            prev = sign
    assert_equal(changes, 1)

    var p0 = ecdf(a, width=400, height=300)
    var p1 = ecdf(b, width=400, height=300)
    var plots: List[Plot] = [p0^, p1^]
    var s = render_layers_svg(plots).to_string()
    assert_equal(_count_tag(s, "path"), 2)
    # 400x300, default theme -> plot_y0=20. Pinned to [0, 1], the
    # staircase's final vertex (y=1) sits exactly on row 20.000; padded
    # to [0, 1.05] it would sit at 20 + 230*0.05/1.05 = 30.952.
    assert_true(
        ",20.000" in s,
        "the proportion axis is pinned to [0, 1]: y=1 lands on plot_y0",
    )
    assert_true(
        ",30.952" not in s,
        "the proportion axis is not padded past 1",
    )
