"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_annotate.mojo`: Tests for Plot.annotate_line(): reference-line placement (raster +
  SVG), the mark-support boundary (Mark.BAR/LINE supported, Mark.ARC
  raises), out-of-range values drawing nothing, and multiple lines
  stacking via repeated calls.

- `test_annotate_area.mojo`: Tests for Plot.annotate_area(): shaded reference-band placement
  (SVG + a raster ink companion), the mark-support boundary (mirroring
  annotate_line()'s), an out-of-range band drawing nothing, a
  partially-out-of-range band clipping to the visible portion instead of
  disappearing, and multiple bands stacking via repeated calls.

- `test_annotate_band.mojo`: Tests for Plot.annotate_band(): a filled region between two curves
  (unlike annotate_area()'s constant (y0, y1) pair) -- hand-derived (via
  a real render, cross-checked by hand) path/label placement, the
  length-mismatch raise, the y_upper < y_lower raise, the mark-support
  boundary (mirroring annotate_point()'s), and clamped-not-crashing
  behavior when a band's x/y overshoot the mark's own domain.

- `test_annotate_best_fit.mojo`: Tests for Plot.annotate_best_fit(): an ordinary-least-squares line
  computed directly from the plot's own already-encoded x/y data --
  hand-derived (cross-checked against a real render) slope/intercept/
  R-squared and line/label placement, both raise paths (too few points,
  a vertical scatter), the mark-support boundary, the all-y-identical
  R-squared special case, and deferred computation (callable before
  .encode() in the fluent chain).

- `test_annotate_facets_layers.mojo`: Tests for Plot.annotate_line()/annotate_area() wired into
  render_facets()/render_layers(): each facet cell's annotations draw
  against that cell's independent y-scale, and each layer's annotations draw against that layer's y-scale (primary or
  secondary), not some other cell's/layer's.

- `test_annotate_vline_point.mojo`: Tests for Plot.annotate_vline()/Plot.annotate_point(): vertical
  reference-line and single-point-marker placement (SVG + raster ink
  companions), out-of-range values/points drawing nothing for each, and
  the mark-support boundary (Mark.LINE supported, Mark.BAR raises --
  narrower than annotate_line()/annotate_area()'s support, since
  neither has a continuous x-axis to place anything against on the nine
  _CategoricalFrame-sharing marks).

"""

from _test_helpers import _assert_color, _assert_near_color
from canvas.color import Color
from dataviz import bar
from dataviz.plot import Plot, render, render_facets_svg, render_layers_svg, render_svg
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_annotate.mojo
# ---------------------------------------------------------------

def test_render_svg_annotate_line_matches_hand_derived_position() raises:
    # 2 categories (A=10, B=20), no gridlines/legend -- the same no-
    # legend geometry test_render_svg_bar_mark_matches_confirmed_rect
    # establishes for this canvas size: plot area x:[60,380],
    # y:[20,250]. _zero_baseline_y_extent([10,20]) pads to domain
    # [0, 21.0] (span 20, 5% pad 1.0), so annotate_line(15.0)'s pixel
    # row is the *same* one the y=15 tick already lands on: y=86 (the
    # tick's label sits at y=90, offset by the same +4 baseline
    # nudge every y-axis tick label already carries). The line spans
    # the full inner width (60 to 380); its label right-aligns
    # just inside the right edge, y=86-4=82.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .annotate_line(15.0, label="mid")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="60" y1="86" x2="380" y2="86" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the reference line itself, spanning the full inner plot width",
    )
    assert_true(
        '<text x="376" y="82" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">mid</text>' in s,
        "the line's label, right-aligned just above it",
    )


def test_render_annotate_line_raster_draws_ink_at_the_hand_derived_row() raises:
    # Raster-side companion to the SVG test above -- confirms canvas_
    # mojo.draw_line_aa actually painted at the same y=86 row, not just
    # that the SVG backend's text/line plumbing is correct.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var _hoisted1 = bar(cats, vals, width=400, height=300, theme=Theme(show_gridlines=False))
    var c = render(_hoisted1)
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).annotate_line(15.0).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var c2 = render(plot)
    # `_assert_near_color()`, not `_assert_color()` -- the reference
    # line is a 1px-wide stroke, the same reason every other mark's
    # axis-line/gridline checks already need the tolerant helper (see
    # its docstring, tests/_test_helpers.mojo).
    _assert_near_color(c2, 220, 86, Color(150, 150, 150), 75, "the reference line's ink, well inside the plot width")


def test_render_annotate_line_out_of_range_value_draws_nothing() raises:
    # A value outside the mark's padded domain ([0, 21.0] for this
    # data) must draw neither a line nor a label -- not clamped to an
    # edge, not extrapolated off-plot into the chrome above (see
    # _draw_annotation_lines's docstring). 25.0 is past the domain's
    # 21.0 max.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .annotate_line(25.0, label="out of range")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true("out of range" not in s, "an out-of-domain annotation draws no label at all")
    assert_true('stroke="#969696"' not in s, "an out-of-domain annotation draws no line at all")


def test_render_annotate_line_multiple_calls_all_draw() raises:
    # .annotate_line() is additive, not a single-slot setter -- two
    # calls both draw, confirmed by counting real annotation-colored
    # <line> elements in the SVG output.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .annotate_line(5.0, label="low")
        .annotate_line(15.0, label="high")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    var count = 0
    var search_from = 0
    while True:
        var idx = s.find('stroke="#969696"', search_from)
        if idx == -1:
            break
        count += 1
        search_from = idx + 1
    assert_equal(count, 2, "both annotation lines draw, not just the most recent call")


def test_render_annotate_line_raises_on_unsupported_mark() raises:
    # Mark.ARC has no continuous y-axis at all -- annotate_line() must
    # raise a clear error rather than silently drawing nothing or
    # drawing somewhere meaningless, the same "raise on a setting that
    # can't apply" rule x_title/y_title-on-Mark.ARC follows.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_arc().encode_categorical(x=cats, y=vals).annotate_line(1.5).size(200, 150)
    with assert_raises():
        var c = render(plot)

# ---------------------------------------------------------------
# from tests/test_annotate_area.mojo
# ---------------------------------------------------------------

def test_render_svg_annotate_area_matches_hand_derived_position() raises:
    # Mark.LINE, 2 points (10 -> 20), no gridlines -- domain pads to
    # roughly [9.5, 20.5] (5% of span 10). annotate_area(12.0, 18.0)'s
    # band maps to y:[72, 198] -- canvas 400x300, plot area x:[60,380],
    # y:[20,250]. Its label sits just inside the band's top
    # edge, right-aligned near the plot's right edge.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_area(12.0, 18.0, label="band").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    # annotation_area_color's default alpha (200/255 -> 0.784, 3
    # decimals) emits a real fill-opacity attribute now, not a fully
    # opaque fill -- see that field's docstring (theme.mojo).
    assert_true(
        '<rect x="60" y="72" width="320" height="126" fill="#e0ecf6" fill-opacity="0.784"/>' in s,
        "the band's fill, spanning the full inner plot width",
    )
    assert_true(
        '<text x="376" y="84" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">band</text>' in s,
        "the band's label, right-aligned just inside its top edge",
    )


def test_render_annotate_area_raster_draws_ink_at_the_hand_derived_row() raises:
    # Raster-side companion to the SVG test above -- confirms canvas_
    # mojo.fill_rect actually painted the band's fill at a point
    # well inside it, not just that the SVG backend's plumbing is
    # correct.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_area(12.0, 18.0).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var c = render(plot)
    # x=200 sits almost exactly on the line's own path at this row (its
    # data value crosses 15.0, the row-150 value, right around x=200) --
    # not a useful "away from the line" point now that the band is real
    # alpha, so this checks x=90 instead, safely off the line's
    # diagonal (its row there is ~228, nowhere near 150). Color(224,
    # 236, 246, 200) blended over the white background (Color.
    # blend_over) -- not the bare annotation_area_color value, since
    # it's real alpha now, not an opaque fill. See that field's
    # docstring (theme.mojo).
    _assert_color(c, 90, 150, Color(230, 240, 247), "the band's fill, well inside the band and away from the line")


def test_render_annotate_area_lets_the_mark_underneath_show_through() raises:
    # The same plot the raster test above uses -- x=200 is where the
    # line's own data value crosses row 150 (see that test's comment),
    # so this point is covered by *both* the mark's stroke and the
    # band's fill. Color(224, 236, 246, 200).blend_over(mark_color)
    # (Color(30, 100, 180), Theme's default) -- not the bare
    # annotation_area_color a fully opaque fill would leave, confirming
    # the band no longer erases the mark drawn underneath it.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_area(12.0, 18.0).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var c = render(plot)
    # `_assert_near_color()`, not `_assert_color()` -- x=200 sits on
    # the line's own 1px-wide stroke, the same reason every other
    # mark's axis-line/gridline checks already need the tolerant
    # helper (see its docstring, tests/_test_helpers.mojo); the band's
    # own fill blended into that isn't exact-pixel-stable either.
    _assert_near_color(c, 200, 150, Color(182, 206, 231), 30, "the band blended over the line's own ink, not erasing it")


def test_render_annotate_area_out_of_range_draws_nothing() raises:
    # A band with *no* overlap at all against the mark's (padded)
    # domain ([9.5, 20.5] for this data) draws neither a fill nor a
    # label -- 25.0-30.0 is entirely past the domain's ~20.5 max.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_area(25.0, 30.0, label="gone").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    # ">gone<" (the label's tag content), not the bare substring
    # "gone" -- Mark.LINE's path already emits a literal `fill=
    # "none"` for its stroke-only fill, so a bare "none" (or any
    # other substring that happens to collide with real SVG markup)
    # would have been a false negative here.
    assert_true(">gone<" not in s, "a fully out-of-domain band draws no label at all")
    assert_true('fill="#e0ecf6"' not in s, "a fully out-of-domain band draws no fill at all -- the hex color alone, unaffected by the fill-opacity attribute alongside it")


def test_render_annotate_area_partial_overlap_clips_to_visible_portion() raises:
    # A band that only *partially* overlaps the domain (18.0-25.0,
    # against a ~20.5 max) draws the clipped, visible portion instead
    # of disappearing entirely: clipped to y:[20, 72] (the plot's top edge down to
    # 18.0's row), not the full, unclipped 18.0-25.0 span.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_area(18.0, 25.0, label="clip").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="60" y="20" width="320" height="52" fill="#e0ecf6" fill-opacity="0.784"/>' in s,
        "the band clips to the plot's top edge rather than disappearing or drawing unclipped",
    )


def test_render_annotate_area_multiple_calls_all_draw() raises:
    # .annotate_area() is additive, not a single-slot setter -- two
    # calls both draw, confirmed by counting real band-colored <rect>
    # elements in the SVG output.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .annotate_area(11.0, 13.0, label="low")
        .annotate_area(16.0, 18.0, label="high")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    var count = 0
    var search_from = 0
    while True:
        var idx = s.find('fill="#e0ecf6"', search_from)
        if idx == -1:
            break
        count += 1
        search_from = idx + 1
    assert_equal(count, 2, "both annotation bands draw, not just the most recent call")


def test_render_annotate_area_raises_on_unsupported_mark() raises:
    # Mark.ARC has no continuous y-axis at all -- annotate_area() must
    # raise a clear error, the same rule annotate_line() follows.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_arc().encode_categorical(x=cats, y=vals).annotate_area(0.5, 1.5).size(200, 150)
    with assert_raises():
        _ = render(plot)

# ---------------------------------------------------------------
# from tests/test_annotate_band.mojo
# ---------------------------------------------------------------

def test_render_svg_annotate_band_matches_hand_derived_path_and_label() raises:
    # Mark.LINE, 2 points (10 -> 20), no gridlines -- canvas 400x300,
    # plot area x:[60,380], y:[20,250] (the exact frame test_annotate_
    # area.mojo's own hand-derived comment already establishes for
    # this identical x/y/size/theme setup). A flat band (y_lower=8,
    # y_upper=22 at both x=1 and x=2) keeps the polygon's math simple:
    # x=1 -> px 74.545, x=2 -> px 365.455 (same to_pixel() the line's
    # own path already uses -- see its "M74.545,239.545 L365.455,
    # 30.455" segment just above the band's own path in the real
    # render this was cross-checked against). y=22 -> py 20.000 (the
    # domain's own top edge, since annotate_area's already-hand-solved
    # padded y-domain here is [9.5, 20.5]... but this band's own values
    # (8/22) sit *outside* that padded mark domain on both edges, so
    # each vertex clamps to the plot rect's own top/bottom (20/250) --
    # see _draw_annotation_bands' own docstring for why a clamped
    # vertex, not a mathematically exact clip, is what this draws.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var y_lo: List[Float64] = [8.0, 8.0]
    var y_hi: List[Float64] = [22.0, 22.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_band(x=x, y_lower=y_lo, y_upper=y_hi, label="CI").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M74.545,20.000 L365.455,20.000 L365.455,250.000 L74.545,250.000 Z" fill="#e0ecf6"'
        ' fill-opacity="0.784"/>' in s,
        "the band's own filled polygon -- top edge left-to-right, then bottom edge back",
    )
    # label centers above band_x[len // 2] = band_x[1] (x=2, the last
    # of 2 points) -- px 365 (Int() truncates 365.455, same truncation
    # the label placement math elsewhere in this package already
    # relies on), py = Int(20.000) - label_gap (4 at this theme's
    # scale) = 16.
    assert_true(
        '<text x="365" y="16" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="middle">CI</text>' in s,
        "the band's label, centered above its own middle-index point",
    )


def test_render_annotate_band_raster_draws_fill_at_a_hand_derived_point() raises:
    # Raster-side companion -- confirms canvas.fill_path_aa
    # actually painted the band's fill, not just that the SVG
    # backend's own path/attribute plumbing is correct. x=90 sits well
    # inside the band and away from the line's own diagonal (same
    # "safely off the line" point test_annotate_area.mojo's own raster
    # test already established for this identical setup).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var y_lo: List[Float64] = [8.0, 8.0]
    var y_hi: List[Float64] = [22.0, 22.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_band(x=x, y_lower=y_lo, y_upper=y_hi).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var c = render(plot)
    _assert_color(c, 90, 150, Color(230, 240, 247), "the band's fill, well inside it and away from the line")


def test_render_raises_on_annotate_band_length_mismatch() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 15.0, 20.0]
    var bad_lo: List[Float64] = [8.0, 9.0]
    var hi: List[Float64] = [12.0, 16.0, 22.0]
    with assert_raises():
        var plot = Plot().mark_line().encode(x=x, y=y).annotate_band(x=x, y_lower=bad_lo, y_upper=hi)
        _ = render_svg(plot)


def test_render_raises_on_annotate_band_inverted_bounds() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var lo: List[Float64] = [12.0, 16.0]
    var hi: List[Float64] = [10.0, 20.0]
    with assert_raises():
        # hi[0]=10.0 < lo[0]=12.0 -- inverted at index 0.
        var plot = Plot().mark_line().encode(x=x, y=y).annotate_band(x=x, y_lower=lo, y_upper=hi)
        _ = render_svg(plot)


def test_render_raises_on_annotate_band_with_an_unsupported_mark() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var x: List[Float64] = [0.0, 1.0]
    var lo: List[Float64] = [0.0, 0.0]
    var hi: List[Float64] = [1.0, 1.0]
    with assert_raises():
        var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).annotate_band(x=x, y_lower=lo, y_upper=hi)
        _ = render_svg(plot)


def test_render_svg_annotate_band_clamps_rather_than_crashes_on_overshoot() raises:
    # A band whose x/y genuinely exceed the mark's own (padded) domain
    # on every edge -- every vertex clamps into the plot rect instead
    # of raising or drawing outside it. Confirms this renders at all
    # (no crash) and that the resulting path stays within the known
    # plot rect bounds (px:[60,380], py:[20,250] -- the same frame
    # every other test in this file uses).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var wide_x: List[Float64] = [-50.0, 50.0]
    var wide_lo: List[Float64] = [-1000.0, -1000.0]
    var wide_hi: List[Float64] = [1000.0, 1000.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_band(x=wide_x, y_lower=wide_lo, y_upper=wide_hi).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    # Every vertex clamps to one of the plot rect's own four corners --
    # the whole polygon collapses to the rect itself.
    assert_true(
        '<path d="M60.000,20.000 L380.000,20.000 L380.000,250.000 L60.000,250.000 Z" fill="#e0ecf6"'
        ' fill-opacity="0.784"/>' in s,
        "every vertex clamped to the plot rect's own corners",
    )

# ---------------------------------------------------------------
# from tests/test_annotate_best_fit.mojo
# ---------------------------------------------------------------

def test_render_svg_annotate_best_fit_matches_hand_derived_fit_and_line() raises:
    # x=[1,2,3,4,5], y=[1,3,2,5,4] -- n=5, sum_x=15, sum_y=15,
    # sum_xy=1+6+6+20+20=53, sum_xx=1+4+9+16+25=55.
    # slope = (5*53 - 15*15) / (5*55 - 15*15) = 40/50 = 0.8
    # intercept = mean_y - slope*mean_x = 3 - 0.8*3 = 0.6
    # SS_tot = sum((y-3)^2) = 4+0+1+4+1 = 10
    # SS_res: predicted 1.4/2.2/3.0/3.8/4.6 -> residuals -0.4/0.8/-1/1.2/-0.6
    #   -> squares 0.16/0.64/1/1.44/0.36 -> sum 3.6
    # R^2 = 1 - 3.6/10 = 0.64
    # Every number independently re-derived via python3 and cross-checked
    # against the actual rendered SVG below (canvas 400x300, no
    # gridlines, plot rect x:[60,380] y:[20,250] -- the same frame every
    # other continuous-axis test in this package derives for this size).
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var plot = Plot().mark_point().encode(x=x, y=y).annotate_best_fit(
        show_equation=True, show_r_squared=True, label="Fit"
    ).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true(
        '<line x1="60" y1="227" x2="380" y2="43" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the fitted line, spanning the full padded x-domain",
    )
    assert_true(
        '<text x="376" y="32" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">Fit</text>' in s,
        "the label heading, right-aligned near the plot's top-right corner",
    )
    assert_true(
        '<text x="376" y="48" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">y = 0.800x + 0.600</text>' in s,
        "the fitted equation, below the label",
    )
    assert_true(
        '<text x="376" y="64" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">R² = 0.640</text>' in s,
        "R-squared, below the equation",
    )


def test_render_svg_annotate_best_fit_draws_only_the_line_with_no_options_set() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var plot = Plot().mark_point().encode(x=x, y=y).annotate_best_fit().theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="60" y1="227" x2="380" y2="43" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the line still draws",
    )
    assert_true("y = " not in s, "no equation text without show_equation=True")
    assert_true("R²" not in s, "no R-squared text without show_r_squared=True")


def test_render_svg_annotate_best_fit_all_y_identical_reports_r_squared_of_one() raises:
    # Every y value identical -- slope comes out to exactly 0.0 (see
    # this method's own docstring), and SS_tot is 0.0, which the
    # implementation defines as R^2 = 1.0 rather than a literal 0/0.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [5.0, 5.0, 5.0, 5.0]
    var plot = Plot().mark_point().encode(x=x, y=y).annotate_best_fit(show_r_squared=True)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true("R² = 1.000" in s, "an all-identical y column is a trivially perfect fit")


def test_render_svg_annotate_best_fit_works_when_called_before_encode() raises:
    # The fit is computed at render() time from whatever x_data/y_data
    # the plot ends up with -- calling this before .encode() in the
    # fluent chain must still see the real data, not an empty column.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var plot = Plot().annotate_best_fit(show_equation=True).mark_point().encode(x=x, y=y).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true("y = 0.800x + 0.600" in s, "the fit sees the data encoded after this call")


def test_render_raises_on_annotate_best_fit_with_fewer_than_two_points() raises:
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [2.0]
    with assert_raises():
        var plot = Plot().mark_point().encode(x=x, y=y).annotate_best_fit()
        _ = render_svg(plot)


def test_render_raises_on_annotate_best_fit_with_a_vertical_scatter() raises:
    var x: List[Float64] = [5.0, 5.0, 5.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises():
        var plot = Plot().mark_point().encode(x=x, y=y).annotate_best_fit()
        _ = render_svg(plot)


def test_render_raises_on_annotate_best_fit_with_an_unsupported_mark() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).annotate_best_fit()
        _ = render_svg(plot)

# ---------------------------------------------------------------
# from tests/test_annotate_facets_layers.mojo
# ---------------------------------------------------------------

def test_render_facets_svg_each_cells_own_annotations_use_that_cells_own_scale() raises:
    # 2 cells, side by side, no gridlines -- cell 1 (y:[0,20]) gets an
    # annotate_line(15.0), cell 2 (y:[0,15]) gets an annotate_area(8,12)
    # -- deliberately different annotation types on different cells, so
    # a bug that used the wrong cell's scale (or drew only one
    # cell's annotation) would show up unambiguously. Canvas 800x300
    # (each cell .size(400, 300), cols=2).
    var cats: List[String] = ["A", "B"]
    var v1: List[Float64] = [10.0, 20.0]
    var v2: List[Float64] = [5.0, 15.0]
    var p1 = Plot().mark_bar().encode_categorical(x=cats, y=v1).annotate_line(15.0, label="mid").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var p2 = Plot().mark_bar().encode_categorical(x=cats, y=v2).annotate_area(8.0, 12.0, label="band").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var plots = List[Plot]()
    plots.append(p1^)
    plots.append(p2^)
    var svg = render_facets_svg(plots, 2)
    var s = svg.to_string()
    assert_true(
        '<line x1="60" y1="86" x2="380" y2="86" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "cell 1's reference line, against its [0,20] domain",
    )
    assert_true(
        '<text x="376" y="82" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">mid</text>' in s,
        "cell 1's reference line label",
    )
    assert_true(
        '<rect x="460" y="75" width="320" height="58" fill="#e0ecf6" fill-opacity="0.784"/>' in s,
        "cell 2's reference band, against its [0,15] domain -- a different position"
        " than it would land at against cell 1's domain",
    )
    assert_true(
        '<text x="776" y="87" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">band</text>' in s,
        "cell 2's reference band label",
    )


def test_render_layers_svg_each_layers_own_annotations_use_that_layers_own_scale() raises:
    # A primary-axis layer (y:[10,20]) and a secondary-axis layer
    # (y:[50,10], reversed) sharing one plot rect -- each gets its annotate_line() at a value chosen so the two land at visibly
    # different rows (12.0 against the primary domain, 40.0 against the
    # secondary one) -- a bug that applied one layer's line to the
    # wrong scale would land at a different, wrong row instead of these
    # exact ones. Canvas 400x300, no gridlines.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [10.0, 20.0]
    var y2: List[Float64] = [50.0, 10.0]
    var primary = Plot().mark_line().encode(x=x, y=y1).annotate_line(12.0, label="primline").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var secondary = (
        Plot()
        .mark_line()
        .encode(x=x, y=y2)
        .secondary_axis()
        .annotate_line(40.0, label="secline")
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var plots = List[Plot]()
    plots.append(primary^)
    plots.append(secondary^)
    var svg = render_layers_svg(plots)
    var s = svg.to_string()
    assert_true(
        '<line x1="60" y1="198" x2="350" y2="198" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the primary layer's reference line, against the primary (left) y-scale",
    )
    assert_true(
        '<text x="346" y="194" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">primline</text>' in s,
        "the primary layer's reference line label",
    )
    assert_true(
        '<line x1="60" y1="83" x2="350" y2="83" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the secondary layer's reference line, against its (right) y-scale -- a"
        " different row than the primary layer's line lands at",
    )
    assert_true(
        '<text x="346" y="79" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="end">secline</text>' in s,
        "the secondary layer's reference line label",
    )

# ---------------------------------------------------------------
# from tests/test_annotate_vline_point.mojo
# ---------------------------------------------------------------

def test_render_svg_annotate_vline_matches_hand_derived_position() raises:
    # Mark.LINE, 2 points (10 -> 20), no gridlines -- x-domain pads to
    # roughly [0.95, 2.05] (5% of span 1.0). annotate_vline(1.5)'s
    # column maps to px=220 -- canvas 400x300, plot area x:[60,380],
    # y:[20,250]. Its label sits just right of the line, near the plot's top edge.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_vline(1.5, label="mid").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="220" y1="20" x2="220" y2="250" stroke="#969696" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "the vertical reference line itself, spanning the full inner plot height",
    )
    assert_true(
        '<text x="224" y="32" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="start">mid</text>' in s,
        "the line's label, left-aligned just right of it, near the top edge",
    )


def test_render_svg_annotate_point_matches_hand_derived_position() raises:
    # Same plot, a point at (1.2, 15.0) -- deliberately a different x
    # than the vline test above, so the two annotation types' ink
    # never overlaps in a raster ink check: cx=133, cy=135 (the same
    # row the "15" y-tick lands on), r=4 (Theme's default point_radius).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_point(1.2, 15.0, label="here").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<circle cx="133" cy="135" r="4" fill="#969696"/>' in s,
        "the point marker itself, at the data coordinate's pixel position",
    )
    assert_true(
        '<text x="133" y="127" font-size="12.000" font-family="sans-serif" fill="#969696"'
        ' text-anchor="middle">here</text>' in s,
        "the point's label, centered just above the marker",
    )


def test_render_annotate_vline_raster_draws_ink_at_the_hand_derived_column() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_vline(1.5).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var c = render(plot)
    # `_assert_near_color()`, not `_assert_color()` -- the vline is a
    # 1px-wide stroke, the same reason every other mark's axis-line/
    # gridline checks already need the tolerant helper (see its
    # docstring, tests/_test_helpers.mojo).
    _assert_near_color(c, 220, 100, Color(150, 150, 150), 40, "the vline's ink, well inside the plot height")


def test_render_annotate_point_raster_draws_ink_at_the_hand_derived_position() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_point(1.2, 15.0).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var c = render(plot)
    _assert_color(c, 133, 135, Color(150, 150, 150), "the point marker's center pixel")


def test_render_annotate_vline_out_of_range_value_draws_nothing() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_vline(5.0, label="gonevl").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(">gonevl<" not in s, "an out-of-domain vline draws no label at all")
    assert_true('stroke="#969696"' not in s, "an out-of-domain vline draws no line at all")


def test_render_annotate_point_out_of_range_draws_nothing() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_line().encode(x=x, y=y).annotate_point(1.5, 100.0, label="gonept").theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(">gonept<" not in s, "an out-of-domain point draws no label at all")
    assert_true("<circle" not in s, "an out-of-domain point draws no marker at all")


def test_render_annotate_vline_raises_on_unsupported_mark() raises:
    # Mark.BAR's x-axis is categorical -- no continuous x value a
    # vertical line could mean anything against, unlike annotate_line()/
    # annotate_area(), which both support Mark.BAR just fine.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).annotate_vline(1.5).size(200, 150)
    with assert_raises():
        _ = render(plot)


def test_render_annotate_point_raises_on_unsupported_mark() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).annotate_point(0.5, 1.5).size(200, 150)
    with assert_raises():
        _ = render(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
