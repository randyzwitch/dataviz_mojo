"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_layers.mojo`: Tests for render_layers/render_layers_svg: shared-domain layering of
  Mark.POINT/LINE/AREA, per-layer color/size encoding and legends, and the
  raises-guards for every mark type layering doesn't support.

- `test_layers_bar_combo.mojo`: Tests for render_layers()'s Mark.BAR combo path (_render_bar_combo_
  layers): a shared categorical x-axis (the bar layer's own categories)
  with Mark.LINE/POINT/AREA layers positioned by index, not by their own
  x values. Hand-derived (cross-checked against a real render) bar/line
  positions, POINT/AREA layer types too, the always-forced zero baseline,
  bars-always-behind draw order, Theme.show_data_labels on the bar layer
  (_draw_bar_rects, shared with the standalone Mark.BAR path), and every
  raise path (a second Mark.BAR layer, a length mismatch, secondary_axis,
  scale_y_log, color/color_categories/size/y_err encoding on a non-bar
  layer, and annotate_*()).

- `test_facets.mojo`: Tests for render_facets/render_facets_svg: independent per-cell layout,
  titles, empty-grid/invalid-cols guards.

- `test_facets_shared_scale.mojo`: Tests for render_facets(shared_y_scale=True): every cell sharing one
  y-domain computed from the union of all cells' own data, instead of
  each computing its own independently. Hand-derived pixel positions
  confirming the shared domain is actually used (not just accepted and
  ignored), and every raise path (an incompatible mark, Mark.AREA
  specifically, Plot.scale_y_log(), and Plot.encode(y_err=...)).

- `test_secondary_axis.mojo`: Tests for Plot.secondary_axis(): render_layers()'s dual-y-axis
  support -- the mirrored right-edge axis line/ticks/labels (SVG + a
  raster ink companion), independent per-axis domains (two very
  differently-shaped series drawing at genuinely different pixel paths,
  not one silently reusing the other's scale), no gridlines drawn for
  the secondary domain, coexistence with a legend column (the two never
  overlap), and both raise paths (a standalone plot, and every layer
  calling .secondary_axis() with none left on the primary axis).

- `test_secondary_axis_caption.mojo`: Tests for the secondary y-axis caption: a layer with .secondary_
  axis() set captions that axis via its .labels(y_title=.), read
  by render_layers()/render_layers_svg() from that specific layer (not
  plots[0]), mirrored onto the plot's right edge with the opposite
  rotation the primary y_title uses. Absent entirely when no secondary-
  axis layer sets one -- the pre-existing, still-default behavior.

"""

from _test_helpers import BG, _assert_color, _count_color
from canvas.color import Color
from canvas.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from dataviz.color_scale import default_categorical_palette
from dataviz.colors import MAGENTA, RED
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

# ---------------------------------------------------------------
# from tests/test_layers_bar_combo.mojo
# ---------------------------------------------------------------

def test_render_layers_svg_bar_combo_matches_hand_derived_positions() raises:
    # 2 categories, canvas 400x300, no gridlines -- plot rect
    # x:[60,380] y:[20,250]. Bar y=[10,20], line y=[15,5] (its own
    # x=[0,1] never read -- see _render_bar_combo_layers's own
    # docstring for why). combined_y=[10,20,15,5] -> zero-baseline
    # domain [0,21] (20's span padded 5% -> +1.0), range [250,20].
    # slope = (20-250)/21 = -10.952380952...
    # Bar A (10): pixel 140.48 -> rect y=140. Bar B (20): pixel
    # 30.95 -> rect y=31. OrdinalScale over 2 categories, range
    # [60,380]: bandwidth=128, center(0)=140, center(1)=300 (this
    # package's usual 0.2-padding split, same as every other 2-
    # category test in this suite). Line: (140, 15->85.714),
    # (300, 5->195.238).
    # Every position independently re-derived via python3 and cross-
    # checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true('<rect x="76" y="140" width="128" height="109" fill="#1e64b4"/>' in s, "bar A")
    assert_true('<rect x="236" y="31" width="128" height="218" fill="#1e64b4"/>' in s, "bar B")
    assert_true(
        '<path d="M140.000,85.714 L300.000,195.238" fill="none" stroke="#1e64b4" stroke-width="2.000"'
        ' stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the line, positioned by category index, not its own x values",
    )


def test_render_layers_svg_bar_combo_draws_the_bar_layer_first() raises:
    # The bar layer's own <rect>s appear before the line's <path> in
    # the SVG's own draw order, regardless of the bar layer's position
    # in the plots list -- see _render_bar_combo_layers's own
    # docstring for why bars always draw first (beneath every other
    # layer). Line listed *before* the bar in `plots` here, the
    # opposite of the test above, to actually exercise that claim.
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var plots: List[Plot] = [line^, bars^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    var rect_index = s.find('<rect x="76" y="140"')
    var path_index = s.find("<path d=")
    assert_true(rect_index != -1 and path_index != -1 and rect_index < path_index, "bar rects precede the line path")


def test_render_layers_svg_bar_combo_supports_a_point_layer() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var point_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var points = Plot().mark_point().encode(x=idx, y=point_y).size(400, 300)
    var plots: List[Plot] = [bars^, points^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true('cx="140" cy="86"' in s, "point A, at its category's band center (85.714 rounds to 86)")
    assert_true('cx="300" cy="195"' in s, "point B (195.238 rounds to 195)")


def test_render_layers_svg_bar_combo_supports_an_area_layer() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var area_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var area = Plot().mark_area().encode(x=idx, y=area_y).size(400, 300)
    var plots: List[Plot] = [bars^, area^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    # Closed down to the zero baseline (pixel 250), pulled 1px to 249
    # since the baseline lands exactly on the axis line -- the same
    # _draw_area_layer technique this reuses (see its own docstring).
    assert_true(
        '<path d="M140.000,85.714 L300.000,195.238 L300.000,249.000 L140.000,249.000 Z"'
        ' fill="#1e64b4"/>' in s,
        "the area, closed down to the shared zero baseline",
    )


def test_render_layers_svg_bar_combo_supports_show_data_labels() raises:
    # Theme.show_data_labels on the bar layer's own Theme -- read via
    # _draw_bar_rects, the same primitive _render_bar's standalone
    # path shares (see that function's own docstring). Same frame as
    # test_render_layers_svg_bar_combo_matches_hand_derived_positions
    # (bar A: rect y=140,h=109 -> label baseline 140-4=136 at x=140;
    # bar B: rect y=31,h=218 -> label baseline 31-4=27 at x=300).
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).theme(
        Theme(show_gridlines=False, show_data_labels=True)
    ).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        '<text x="140" y="136" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>' in s,
        "bar A's own data label",
    )
    assert_true(
        '<text x="300" y="27" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">20</text>' in s,
        "bar B's own data label",
    )


def test_render_layers_raises_on_a_second_bar_layer() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var bars1 = Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    var bars2 = Plot().mark_bar().encode_categorical(x=cats, y=vals).size(400, 300)
    var plots: List[Plot] = [bars1^, bars2^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_a_non_bar_layer_length_mismatch() raises:
    var cats: List[String] = ["A", "B", "C"]
    var bar_y: List[Float64] = [10.0, 20.0, 15.0]
    var bad_idx: List[Float64] = [0.0, 1.0]
    var bad_y: List[Float64] = [5.0, 6.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    var line = Plot().mark_line().encode(x=bad_idx, y=bad_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_secondary_axis_in_a_bar_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300).secondary_axis()
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_scale_y_log_in_a_bar_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [1.0, 2.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300).scale_y_log()
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_color_categories_on_a_non_bar_layer() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var color_cats: List[String] = ["x", "y"]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    var points = Plot().mark_point().encode(x=idx, y=line_y, color_categories=color_cats).size(400, 300)
    var plots: List[Plot] = [bars^, points^]
    with assert_raises():
        _ = render_layers_svg(plots)


def test_render_layers_raises_on_annotate_line_in_a_bar_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar().encode_categorical(x=cats, y=bar_y).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300).annotate_line(15.0)
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)

# ---------------------------------------------------------------
# from tests/test_facets.mojo
# ---------------------------------------------------------------

def test_render_facets_lays_out_independent_plots_side_by_side() raises:
    # Two cells, 400x300 each, side by side on an 800x300 canvas (cols=2,
    # so rows=1) -- cell 0 is x:[0,400], y:[0,300], the *exact* same
    # dimensions test_render_point_mark_centers_on_the_hand_derived_pixel
    # already hand-solved for a single (5.0, 5.0) point with Theme's
    # default margins: plot area x:[60,380], y:[20,250], point pixel
    # (220, 135). Cell 1 is x:[400,800], y:[0,300] -- identical geometry,
    # just shifted +400 in x (`render()`'s ox0 offsets everything,
    # including the margins, so the whole plot area shifts by the same
    # +400, not just its origin) -- plot area x:[460,780], point pixel
    # (620, 135) confirmed by the same offset, not re-solved from
    # scratch. Two different mark_colors (one per plot's Theme)
    # confirm each cell actually rendered its independent plot, not
    # one plot's output bleeding into or overwriting the other's cell.
    #
    # render_facets() derives its 800x300 canvas from each plot's own
    # .size(400, 300) (both plots must agree -- see _require_uniform_
    # size's docstring), rather than a canvas the caller builds by hand.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy).size(400, 300)
    var plot1 = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(mark_color=RED)).size(400, 300)
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var c = render_facets(plots, cols=2)

    _assert_color(c, 220, 135, Theme.default().mark_color, "cell 0's point, unshifted")
    _assert_color(c, 620, 135, RED, "cell 1's point, +400px shifted")


def test_render_facets_leaves_trailing_cells_blank_when_plots_dont_fill_the_grid() raises:
    # 3 plots, cols=2 -> rows=ceil(3/2)=2, a 2x2 grid of 400x300 cells
    # on an 800x600 canvas (800/2=400, 600/2=300 -- divides evenly, no
    # rounding to reason about here). Plots fill row-major: (0,0),
    # (0,1), (1,0); (1,1) has no 4th plot and is never touched.
    #
    # Each filled cell reuses the same hand-solved single-(5.0,5.0)-point
    # geometry as the side-by-side test above, offset by its cell's
    # origin: (0,0) -> point at (220,135) [unshifted]; (0,1) -> (620,135)
    # [+400 in x]; (1,0) -> plot area y:[320,550] (cell_y0=300, so
    # +300 in y throughout), point at (220,435) [+300 in y].
    #
    # Every plot's Theme.background is set to a color no default Theme
    # ever produces (10,20,30, not white) specifically so a genuinely
    # untouched cell (the render()-constructed canvas's own default
    # white fill) is distinguishable from one that was rendered.
    var xy: List[Float64] = [5.0]
    var theme = Theme(background=Color(10, 20, 30))
    var plot0 = Plot().mark_point().encode(x=xy, y=xy).theme(theme).size(400, 300)
    var plot1 = Plot().mark_point().encode(x=xy, y=xy).theme(theme).size(400, 300)
    var plot2 = Plot().mark_point().encode(x=xy, y=xy).theme(theme).size(400, 300)
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)
    plots.append(plot2^)

    var c = render_facets(plots, cols=2)

    var mark_color = Theme.default().mark_color
    _assert_color(c, 220, 135, mark_color, "cell (0,0)'s point")
    _assert_color(c, 620, 135, mark_color, "cell (0,1)'s point")
    _assert_color(c, 220, 435, mark_color, "cell (1,0)'s point")
    _assert_color(c, 700, 450, Color(255, 255, 255), "cell (1,1) has no 4th plot -- never touched, stays the canvas's own white default")


def test_render_facets_raises_on_non_positive_cols() raises:
    # A non-empty, uniformly sized list -- cols<=0 is what this test
    # means to exercise, not the separate "plots must not be empty"
    # guard _require_uniform_size raises first for an empty list (see
    # test_render_facets_with_empty_list_raises below).
    var xy: List[Float64] = [5.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_point().encode(x=xy, y=xy).size(400, 300))
    with assert_raises():
        _ = render_facets(plots, cols=0)
    with assert_raises():
        _ = render_facets(plots, cols=-1)


def test_render_facets_with_empty_list_raises() raises:
    # A prior version of this function took a caller-supplied canvas
    # and treated an empty plots list as a no-op against it; now that
    # render_facets() builds its own canvas from the plots list, there's
    # no plot left to derive a size from, so an empty list raises
    # instead (see _require_uniform_size's docstring).
    var plots = List[Plot]()
    with assert_raises():
        _ = render_facets(plots, cols=2)


def test_render_facets_svg_lays_out_independent_plots_side_by_side() raises:
    # The exact same setup test_render_facets_lays_out_independent_
    # plots_side_by_side already hand-solved for the raster path: two
    # 400x300 cells side by side on an 800x300 canvas (cols=2, rows=1),
    # each a single (5.0, 5.0) point -- cell 0's point at (220,
    # 135) [unshifted], cell 1's at (620, 135) [+400 in x, the same
    # cell-origin-offset reasoning that test's comment explains].
    # Two different mark_colors confirm each cell rendered its independent plot into the shared SvgCanvas, not one overwriting
    # the other.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy).size(400, 300)
    var plot1 = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(mark_color=RED)).size(400, 300)
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
    # Same two-cell 800x300 layout (cols=2) as the test just above, but
    # cell 0's Plot sets a title (via .labels()) and cell 1's
    # doesn't -- confirming render_facets()'s per-cell Plot.labels()
    # support (the wiki's Changelog, its "Plot.labels() reaches
    # render_facets/render_layers" entry): the title reserves space
    # *only* in cell 0 -- its point shifts from (220,135), the
    # no-title baseline the test above established, down to
    # (220,146) (extra_top=Int(18.0)+4=22 pushes plot_y0 from 20 to 42,
    # moving the y=[4,6]-padded-domain midpoint pixel from
    # (20+250)/2=135 to (42+250)/2=146) -- while cell 1's point
    # stays exactly where it was (620,135), no title there to reserve
    # room for. The title itself centers at
    # ((60+380)//2, Int(18.0*0.8))=(220,14), cell 0's inner rect,
    # unaffected by cell 1's layout.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy).labels(title="Left").size(400, 300)
    var plot1 = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(mark_color=RED)).size(400, 300)
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var svg = render_facets_svg(plots, cols=2)
    var s = svg.to_string()

    assert_true(
        '<text x="220" y="14" font-size="18.000" font-family="sans-serif" font-weight="bold" fill="#282828"'
        ' text-anchor="middle">Left</text>' in s,
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
    # render_facets() fills each cell's full rect, the same contract
    # render() documents ("the whole original rect is filled . so a
    # title's reserved margin strip gets painted too") -- a titled
    # cell's reserved title strip must get painted, not left showing
    # whatever the canvas held beforehand.
    #
    # Proven via a distinctive Theme.background (MAGENTA) rather than a
    # caller-prefilled canvas -- render_facets() builds its own canvas
    # now (always starting from Canvas's own white default), so the
    # only way pixel (2,2) ends up MAGENTA is a real fill_rect reaching
    # it, exactly the same proof the old MAGENTA-prefilled-canvas
    # version made, just inverted (white -> MAGENTA instead of
    # MAGENTA -> white). One cell (cols=1), title_font_size=18.0 and
    # label_gap=4 make extra_top=22, so y=2 sits inside the reserved
    # strip and above the plot area entirely.
    var xy: List[Float64] = [5.0]
    var plots = List[Plot]()
    plots.append(
        Plot().mark_point().encode(x=xy, y=xy).labels(title="Titled").theme(Theme(background=MAGENTA)).size(400, 300)
    )

    var c = render_facets(plots, 1)
    _assert_color(c, 2, 2, MAGENTA, "a titled cell's reserved title strip")

    # .and the same for an untitled cell, where the strip doesn't
    # exist but the corner is still outside the plot area -- confirming
    # the fill covers the ordinary case too, not just the titled one.
    var untitled = List[Plot]()
    untitled.append(Plot().mark_point().encode(x=xy, y=xy).theme(Theme(background=MAGENTA)).size(400, 300))
    var c2 = render_facets(untitled, 1)
    _assert_color(c2, 2, 2, MAGENTA, "an untitled cell's top-left corner")

# ---------------------------------------------------------------
# from tests/test_facets_shared_scale.mojo
# ---------------------------------------------------------------

def test_render_facets_svg_shared_y_scale_matches_hand_derived_positions() raises:
    # Two cells, one point each: y=10 and y=110. Combined domain data
    # [10, 110] -- span 100, padded 5% (5.0) -> [5, 115]. Each cell is
    # 400x300 (rows=1, cols=2 -> cell height stays the full 300), default
    # theme -> plot_y0 = margin_top (20), plot_y1 = height - margin_bottom
    # (300-50=250) for *both* cells (same row).
    #
    # scale() = (20-250)/(115-5) = -230/110 = -2.0909...
    # translate() = 250 - 5*scale() = 260.4545...
    # to_pixel(10)  = 239.545... -> rounds to 240 (cell 0's own point)
    # to_pixel(110) = 30.454...  -> rounds to 30  (cell 1's own point)
    #
    # If each cell computed its own independent domain instead (the
    # shared_y_scale=False default), cell 0's lone y=10 point would be a
    # zero-span domain (pad=1.0 fallback -> domain [9,11]) landing at a
    # completely different pixel row -- so this also confirms the shared
    # domain is genuinely being used, not silently ignored.
    var x: List[Float64] = [1.0]
    var y0: List[Float64] = [10.0]
    var y1: List[Float64] = [110.0]
    var p0 = Plot().size(400, 300).mark_point().encode(x=x, y=y0)
    var p1 = Plot().size(400, 300).mark_point().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    var s = render_facets_svg(plots, 2, shared_y_scale=True).to_string()
    assert_true('cy="240"' in s, "cell 0's own point (y=10) lands at the hand-derived shared-scale row")
    assert_true('cy="30"' in s, "cell 1's own point (y=110) lands at the hand-derived shared-scale row")


def test_render_facets_raises_on_an_incompatible_mark_with_shared_y_scale() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var p0 = Plot().size(300, 220).mark_bar().encode_categorical(x=cats, y=vals)
    var p1 = Plot().size(300, 220).mark_bar().encode_categorical(x=cats, y=vals)
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_raises_on_mark_area_with_shared_y_scale() raises:
    # Mark.AREA is deliberately excluded even though it's otherwise
    # part of the "continuous" family -- its own forced zero baseline
    # has no principled way to compose with an externally shared domain.
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 6.0]
    var y1: List[Float64] = [50.0, 60.0]
    var p0 = Plot().size(300, 220).mark_area().encode(x=x, y=y0)
    var p1 = Plot().size(300, 220).mark_area().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_raises_on_scale_y_log_with_shared_y_scale() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 6.0]
    var y1: List[Float64] = [50.0, 60.0]
    var p0 = Plot().size(300, 220).mark_line().encode(x=x, y=y0).scale_y_log()
    var p1 = Plot().size(300, 220).mark_line().encode(x=x, y=y1).scale_y_log()
    var plots: List[Plot] = [p0^, p1^]
    with assert_raises():
        _ = render_facets(plots, 2, shared_y_scale=True)


def test_render_facets_raises_on_y_err_with_shared_y_scale() raises:
    # The shared union (_render_facets_generic's own combined_y) is
    # computed over plain plot.y_data, not widened for whisker
    # endpoints the way a standalone plot's own y_domain_data is --
    # so this combination raises rather than silently risking a
    # clipped whisker. Mark.POINT, not Mark.LINE (Mark.LINE doesn't
    # support y_err at all, a separate, pre-existing restriction).
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
    # shared_y_scale defaults to False -- confirms the existing,
    # already-tested independent-per-cell behavior is unchanged: two
    # single-point cells (zero-span domains) each get their own
    # domain_min/max +/- the 1.0 fallback pad, landing both points at
    # the exact same pixel row (each cell's own point sits dead center
    # of its own [y-1, y+1] domain), unlike the shared case above where
    # they land at very different rows.
    var x: List[Float64] = [1.0]
    var y0: List[Float64] = [10.0]
    var y1: List[Float64] = [110.0]
    var p0 = Plot().size(400, 300).mark_point().encode(x=x, y=y0)
    var p1 = Plot().size(400, 300).mark_point().encode(x=x, y=y1)
    var plots: List[Plot] = [p0^, p1^]
    var s = render_facets_svg(plots, 2).to_string()
    # domain [9, 11], range [250, 20] -> to_pixel(10) = 135.0 exactly,
    # the same middle row for *both* cells independently.
    var count = 0
    var search_from = 0
    while True:
        var idx = s.find('cy="135"', search_from)
        if idx == -1:
            break
        count += 1
        search_from = idx + 1
    assert_true(count == 2, "both cells' own independent domain centers their lone point at row 135")

# ---------------------------------------------------------------
# from tests/test_secondary_axis.mojo
# ---------------------------------------------------------------

def test_render_layers_svg_secondary_axis_matches_hand_derived_position() raises:
    # 2 layers, no color/size encoding (so legend_reserve is 0) --
    # gridlines stay on (default Theme) specifically to confirm the
    # *secondary* domain draws none of its own (see the gridline-count
    # assertion below). Two points each,
    # canvas 400x300: primary line rises 10->20 (matches test_layers.
    # mojo's no-legend geometry -- plot area x:[60,342], y:[20,250]
    # before the secondary axis's reserve shrinks px1 further, to
    # 350). Secondary line falls 50->10 -- a deliberately different
    # shape/scale from the primary series, so a wrong implementation
    # that silently reused the primary y_scale would draw a visibly
    # different (flattened/off-plot) path instead of this one.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).size(400, 300)
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis().size(400, 300)
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()

    assert_true(
        '<path d="M73.182,239.545 L336.818,30.455" fill="none" stroke="#1e64b4" stroke-width="2.000"'
        ' stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the primary layer's rising path, against the primary (left) y-scale",
    )
    assert_true(
        '<path d="M73.182,30.455 L336.818,239.545" fill="none" stroke="#1e64b4" stroke-width="2.000"'
        ' stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the secondary layer's falling path -- the opposite slope, against its own"
        " independent (right) y-scale, not the primary one",
    )
    assert_true(
        '<line x1="350" y1="20" x2="350" y2="250" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the secondary axis's vertical line, mirrored onto the plot's right edge",
    )
    assert_true(
        '<line x1="350" y1="135" x2="355" y2="135" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "one of the secondary axis's ticks, pointing right instead of left",
    )
    assert_true(
        '<text x="359" y="139" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="start">30</text>' in s,
        "that tick's label, left-aligned just past it -- the mirror of the primary"
        " axis's right-aligned labels sitting just before its ticks",
    )


def test_render_layers_svg_secondary_axis_draws_no_gridlines_of_its_own() raises:
    # Same setup as above -- exactly 6 gridlines expected (3 vertical
    # from the shared x-axis, 3 horizontal from the *primary* y-domain's
    # own 3 ticks: 10/15/20), even though the secondary y-domain has 5
    # ticks of its own (10/20/30/40/50) -- confirms none of those 5
    # spawn a 4th, 5th, 6th, 7th, 8th gridline of their own.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).size(400, 300)
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis().size(400, 300)
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
    assert_equal(count, 6, "only the shared x-axis's and the primary y-axis's gridlines draw")


def test_render_layers_secondary_axis_raster_draws_ink_at_the_hand_derived_row() raises:
    # Raster-side companion to the SVG tests above -- confirms canvas_
    # mojo's draw_line_aa actually painted the secondary axis's tick at
    # the same (350, 135) position, not just that the SVG backend's
    # line/text plumbing is correct. x=349, not the axis line's own
    # nominal x=350 -- render_layers()'s supersample-then-downsample
    # (`_RASTER_SUPERSAMPLE`, plot.mojo) spreads the tick's 1px-wide ink
    # across columns 349-354 rather than concentrating it at exactly
    # one; 349 is where it happens to land fully opaque.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).size(400, 300)
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis().size(400, 300)
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var c = render_layers(plots)
    _assert_color(c, 349, 135, Color(80, 80, 80), "the secondary axis's tick, just right of its axis line")


def test_render_layers_svg_secondary_axis_coexists_with_a_legend_without_overlap() raises:
    # A color-categories-encoded Mark.POINT primary layer (so a real
    # legend column draws) alongside a secondary-axis Mark.LINE layer --
    # confirms the legend column shifts right past the secondary axis's
    # reserved tick-label width instead of overlapping it. The
    # secondary axis's line lands at x=220 (shrunk further than the
    # no-legend case's x=350 above, since legend_reserve is folded in
    # too), its widest tick label ("50") ends well before x=270, where the first
    # legend swatch actually starts.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_point().encode(x=x, y=y1, color_categories=cats).size(400, 300)
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis().size(400, 300)
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        '<line x1="220" y1="20" x2="220" y2="250" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the secondary axis's line, shrunk further left to also make room for the legend",
    )
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "the legend's first swatch, starting well clear of the secondary axis's labels",
    )


def test_render_secondary_axis_raises_on_standalone_render() raises:
    # Plot.secondary_axis() only means anything inside render_layers()/
    # render_layers_svg() -- a standalone render() call must raise
    # rather than silently ignoring it (there's no second series for it
    # to pair against).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).secondary_axis().size(200, 150)
    with assert_raises():
        _ = render(plot)


def test_render_layers_raises_when_every_layer_is_secondary() raises:
    # At least one layer must stay on the primary axis -- every layer
    # calling .secondary_axis() leaves nothing for "secondary" to mean
    # relative to, so render_layers() must raise rather than silently
    # treating it as an ordinary single shared axis.
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
    # Primary layer (y:[10,20]) with no caption, secondary layer
    # (y:[50,10]) captioned "Growth" via its .labels(y_title=.) --
    # canvas 400x300, no gridlines: the secondary axis's line shrinks
    # further left (to x=332, from the no-caption case's x=350) to
    # make room, and the caption itself draws rotated +90 degrees
    # (the opposite of the primary y_title's -90), centered at
    # (389, 135) -- the vertical midpoint of the shared plot rect.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).theme(Theme(show_gridlines=False)).size(400, 300)
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
        '<text x="389" y="135" font-size="14.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle" transform="rotate(90.000 389 135)">Growth</text>' in s,
        "the secondary axis's caption, rotated the opposite way from the primary y_title",
    )
    assert_true(
        '<line x1="332" y1="20" x2="332" y2="250" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the secondary axis's line, shrunk further left to also make room for its caption",
    )


def test_render_layers_svg_no_caption_when_secondary_axis_has_no_y_title() raises:
    # The pre-existing, still-default case: a secondary-axis layer with
    # no .labels(y_title=.) draws no caption at all, and the
    # secondary axis's line lands at its no-caption position
    # (x=350, not x=332 -- matching tests/test_secondary_axis.
    # mojo's already-established geometry for this exact setup).
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).theme(Theme(show_gridlines=False)).size(400, 300)
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis().theme(Theme(show_gridlines=False)).size(400, 300)
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true("rotate(90" not in s, "no secondary-axis caption text draws when y_title is unset")
    assert_true(
        '<line x1="350" y1="20" x2="350" y2="250" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the secondary axis's line lands at its no-caption position, unaffected",
    )


def test_render_layers_svg_primary_layers_own_y_title_is_not_mistaken_for_a_caption() raises:
    # plots[0] (the primary layer) setting its y_title must still
    # draw on the *left* the normal way -- only a layer that actually
    # called .secondary_axis() triggers the right-side caption logic.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).labels(y_title="Primary").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var secondary = Plot().mark_line().encode(x=x, y=y2).secondary_axis().theme(Theme(show_gridlines=False)).size(400, 300)
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true("rotate(-90" in s, "the primary layer's y_title still draws, rotated the usual way")
    assert_true("rotate(90.000" not in s, "no right-side caption draws just because plots[0] set a y_title")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
