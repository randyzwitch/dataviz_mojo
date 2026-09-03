"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_horizontal_bar.mojo`: Tests for `Plot.mark_bar(horizontal=True)`/`bar(..., horizontal=True)`
  (#121): `_render_horizontal_bar`'s rectangles, negative values
  extending left of the baseline instead of below it, the 1px pull-off
  when the baseline lands exactly on the frame's left axis line,
  `Theme.color_by_sign`/`show_data_labels` support (mirroring the
  vertical `Mark.BAR` path's own), the quickplot `bar()` function
  matching the fluent `Plot.mark_bar(horizontal=True)` builder exactly,
  and the one raise path: a horizontal bar layer inside `render_layers()`.

- `test_horizontal_beeswarm.mojo`: Tests for `Plot.mark_beeswarm(horizontal=True)`/`beeswarm(...,
  horizontal=True)` (#121): `_render_horizontal_beeswarm`'s jittered
  point positions, the quickplot `beeswarm()` function matching the
  fluent `Plot.mark_beeswarm(horizontal=True)` builder exactly (both the
  concrete and `DType`-generic overload), and the same raise paths
  `_render_beeswarm`'s own validation gives.

- `test_horizontal_box.mojo`: Tests for `Plot.mark_box(horizontal=True)`/`box(..., horizontal=True)`
  (#121): `_render_horizontal_box`'s box/whisker rectangles and outlier
  placement, the quickplot `box()` function matching the fluent `Plot.
  mark_box(horizontal=True)` builder exactly (both the concrete and
  `DType`-generic overload), and the same length-mismatch raise
  `_render_box`'s own validation gives.

- `test_horizontal_grouped_bar.mojo`: Tests for `Plot.mark_grouped_bar(horizontal=True)`/`grouped_bar(...,
  horizontal=True)` (#121): `_render_horizontal_grouped_bar`'s
  sub-bar rectangles and legend placement, `Theme.show_data_labels`
  support with mixed-sign values, the quickplot `grouped_bar()` function
  matching the fluent `Plot.mark_grouped_bar(horizontal=True)` builder
  exactly (both the concrete and `DType`-generic overload), and the
  empty-data case.

- `test_horizontal_lollipop.mojo`: Tests for `Plot.mark_lollipop(horizontal=True)`/`lollipop(...,
  horizontal=True)` (#121): `_render_horizontal_lollipop`'s stem+point
  positions, the 1px pull-off when the baseline lands exactly on the
  frame's left axis line (mirroring `_render_horizontal_bar`'s own), the
  quickplot `lollipop()` function matching the fluent `Plot.mark_lollipop(
  horizontal=True)` builder exactly (both the concrete and the `DType`-
  generic overload), and the empty-data case.
  
  Unlike `Mark.BAR`, `Mark.LOLLIPOP` doesn't support `Theme.
  color_by_sign`/`show_data_labels` (neither does the vertical path --
  see `_render_lollipop`), and isn't a valid `render_layers()` combo
  layer at all regardless of orientation (only `Mark.BAR` gets a combo
  path; `Mark.LOLLIPOP` already hits the generic "only Mark.POINT/LINE/
  AREA can be layered" raise, unrelated to `horizontal`), so neither gets
  a horizontal-specific test here.

- `test_horizontal_stacked_bar.mojo`: Tests for `Plot.mark_stacked_bar(horizontal=True)`/`stacked_bar(...,
  horizontal=True)` (#121): `_render_horizontal_stacked_bar`'s segment
  rectangles and legend placement, `percent=True` combined with
  `horizontal=True` (a fixed `[0, 100]` x-axis), the quickplot
  `stacked_bar()` function matching the fluent `Plot.mark_stacked_bar(
  horizontal=True)` builder exactly (both the concrete and `DType`-
  generic overload), and the empty-data case.

- `test_horizontal_violin.mojo`: Tests for `Plot.mark_violin(horizontal=True)`/`violin(...,
  horizontal=True)` (#121): `_render_horizontal_violin`'s silhouette
  path (spot-checked at hand-derived points, the KDE curve itself being
  too dense to fully re-derive by hand -- the same tolerance test_
  violin.mojo's own tests take), the quickplot `violin()` function
  matching the fluent `Plot.mark_violin(horizontal=True)` builder
  exactly (both the concrete and `DType`-generic overload), `bandwidth`/
  `scale_by_count` combined with `horizontal=True`, and the negative-
  bandwidth raise.

"""

from dataviz import bar, beeswarm, box, grouped_bar, lollipop, stacked_bar, violin
from dataviz.plot import Plot, render_layers_svg, render_svg
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_horizontal_bar.mojo
# ---------------------------------------------------------------

def test_render_svg_horizontal_bar_matches_hand_derived_rectangles() raises:
    # 2 categories, values=[10, -5], canvas 640x420 default margins
    # (plot area x:[60,620] y:[20,370]). _zero_baseline_y_extent pads
    # only the non-zero-crossing end of [-5,10] (span 15, 5% pad
    # 0.75) to [-5.75, 10.75] -- baseline (0) pixel:
    # 60 + (0-(-5.75))/16.5*560 = 255.15 -> 255 (matches the "0" tick
    # this same render confirms independently). Bar A (10):
    # 60 + (10-(-5.75))/16.5*560 = 594.55 -> 595, rect x=min(255,595)=
    # 255, width=340. Bar B (-5): 60 + (-5-(-5.75))/16.5*560 = 85.45 ->
    # 85, rect x=min(255,85)=85, width=170. Neither edge lands on
    # px0=60, so no 1px pull-off applies here (see the sibling test
    # below for that case). Every position independently re-derived
    # via python3 and cross-checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var plot = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="255" y="38" width="340" height="140" fill="#1e64b4"/>' in s, "bar A, extending right")
    assert_true('<rect x="85" y="213" width="170" height="140" fill="#1e64b4"/>' in s, "bar B, extending left")
    assert_true('<text x="255" y="391"' in s and ">0</text>" in s, "the 0 tick lands where the baseline math predicts")


def test_render_horizontal_bar_pulls_off_axis_line_when_baseline_touches_left_edge() raises:
    # All-positive data -- the domain's low end stays exactly 0
    # (unpadded), so the baseline lands exactly on the frame's own
    # left axis line (px0=60) -- _pull_off_axis_line should nudge
    # every bar's left edge to 61, the same hairline-of-background
    # protection the vertical Mark.BAR path already gets at its own
    # bottom edge.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False)
    )
    var s = render_svg(plot).to_string()
    assert_true('<rect x="61" y="38" width="266" height="140" fill="#1e64b4"/>' in s, "bar A pulled off the axis line")
    assert_true('<rect x="61" y="213" width="532" height="140" fill="#1e64b4"/>' in s, "bar B pulled off the axis line")


def test_render_horizontal_bar_color_by_sign() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var plot = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=vals).theme(t)
    var s = render_svg(plot).to_string()
    assert_true(
        '<rect x="255" y="38" width="340" height="140" fill="#1e64b4"/>' in s,
        "positive bar keeps mark_color even with color_by_sign on",
    )
    assert_true(
        '<rect x="85" y="213" width="170" height="140" fill="#c83c3c"/>' in s,
        "negative bar uses mark_color_negative",
    )


def test_render_svg_horizontal_bar_supports_show_data_labels() raises:
    # Same frame as the hand-derived rectangles test above. Bar A
    # (positive, rect x=255,w=340 -> right edge 595): label sits
    # label_gap(4) right of that edge, left-aligned, vertically
    # centered on its own row (y=38,h=140 -> center 108, +Int(12*0.35)=4
    # -> 112). Bar B (negative, rect x=85 -> left edge 85): label sits
    # 4px left of it, right-aligned, row y=213,h=140 -> center 283,
    # +4 -> 287.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var plot = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False, show_data_labels=True)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<text x="599" y="112" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="start">10</text>' in s,
        "bar A's label, right of the bar, left-aligned",
    )
    assert_true(
        '<text x="81" y="287" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="end">-5</text>' in s,
        "bar B's label, left of the bar, right-aligned",
    )


def test_bar_horizontal_matches_plot_mark_bar_horizontal() raises:
    # The quickplot bar(horizontal=True) convenience function must
    # render identically to the fluent builder it wraps -- the same
    # equivalence test_quickplot.mojo's own test_bar_matches_manual_
    # plot establishes for the vertical (default) case.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var t = Theme(show_gridlines=False)
    var from_quickplot = bar(cats, vals, theme=t, horizontal=True)
    var from_builder = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=vals).theme(t)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())


def test_render_horizontal_bar_empty_data_only_fills_background() raises:
    var plot = Plot().mark_bar(horizontal=True).size(50, 40)  # no encode_categorical() call
    var s = render_svg(plot).to_string()
    assert_true("<rect" in s, "still fills the background")
    assert_true("<line" not in s, "no axis lines drawn for zero categories")


def test_render_layers_raises_on_horizontal_bar_in_a_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = Plot().mark_bar(horizontal=True).encode_categorical(x=cats, y=bar_y).size(400, 300)
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)

# ---------------------------------------------------------------
# from tests/test_horizontal_beeswarm.mojo
# ---------------------------------------------------------------

def test_render_svg_horizontal_beeswarm_matches_hand_derived_offsets() raises:
    # Same data as test_beeswarm.mojo's own hand-derived test: 1
    # category ("A"), values [10, 11, 50] -- 10 and 11 land close
    # enough in pixel space to collide, 50 stays alone. Canvas
    # 400x300, show_gridlines=False -- the horizontal mirror of that
    # test's own [60,380]x[20,250]y frame, both axes swapped: x-domain
    # = _data_extent([10,11,50]) = [8,52] now runs left-to-right
    # (pixel x's 75 (v=10), 82 (v=11), 365 (v=50)), 1 category spans
    # the whole y-band (center=135). Unlike the vertical case (where
    # the y-axis is flipped, so 11 sorts before 10 in pixel space), the
    # x-axis here runs the same direction as the values, so 10 (pixel
    # 75) sorts before 11 (pixel 82): 10 gets offset 0 (first in its
    # row), 11 gets offset +8 (second). Every position independently
    # re-derived via python3 and cross-checked against the actual
    # rendered SVG.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 11.0, 50.0]]
    var plot = Plot().mark_beeswarm(horizontal=True).encode_distribution(categories=cats, values=vals).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<circle cx="75" cy="135" r="4" fill="#1e64b4"/>' in s, "value 10 -- offset 0 (first in its row)")
    assert_true('<circle cx="82" cy="143" r="4" fill="#1e64b4"/>' in s, "value 11 -- offset +8 (second in its row)")
    assert_true('<circle cx="365" cy="135" r="4" fill="#1e64b4"/>' in s, "value 50 -- offset 0 (alone in its row)")


def test_beeswarm_horizontal_matches_plot_mark_beeswarm_horizontal() raises:
    # The quickplot beeswarm(horizontal=True) convenience function must
    # render identically to the fluent builder it wraps, and the
    # DType-generic overload must forward horizontal too (see
    # lollipop's own equivalent test -- a forwarding bug there was
    # caught this exact way).
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 11.0, 50.0]]
    var int_vals: List[List[Int]] = [[10, 11, 50]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = beeswarm(cats, vals, theme=t, horizontal=True)
    var from_builder = Plot().mark_beeswarm(horizontal=True).encode_distribution(categories=cats, values=vals).theme(t)
    var from_dtype = beeswarm(cats, int_vals, theme=t, horizontal=True)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())
    assert_equal(render_svg(from_dtype).to_string(), render_svg(from_builder).to_string())


def test_render_horizontal_beeswarm_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[List[Float64]] = [[1.0]]
    with assert_raises():
        var plot = beeswarm(cats, vals, width=200, height=150, horizontal=True)
        _ = render_svg(plot)


def test_render_horizontal_beeswarm_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[List[Float64]]()
    var plot = beeswarm(cats, vals, width=200, height=150, horizontal=True)
    var s = render_svg(plot).to_string()
    assert_true("<rect" in s, "still fills the background")
    assert_true("<line" not in s, "no axis lines drawn for zero categories")

# ---------------------------------------------------------------
# from tests/test_horizontal_box.mojo
# ---------------------------------------------------------------

def test_render_svg_horizontal_box_matches_hand_derived_rects_and_outlier() raises:
    # Same data as test_box.mojo's own hand-derived test: "A" =
    # [2,4,4,4,5,5,7,9,20] (q1=4, median=5, q3=7, low=2, high=9, one
    # outlier at 20), "B" = [10,12,14,15,18] (q1=12, median=14, q3=15,
    # low=10, high=18, no outliers). Canvas 400x300, show_gridlines=
    # False -- the horizontal mirror of that test's own [60,380]x
    # [20,250]y frame, both axes swapped: domain [1.1, 20.9] now runs
    # left-to-right, 2 categories run top-to-bottom (band centers
    # 78/193, bandwidth 92). Every position independently re-derived
    # via python3 and cross-checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var plot = Plot().mark_box(horizontal=True).encode_boxplot(cats, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<rect x="107" y="32" width="48" height="92" fill="#1e64b4"/>' in s, "A's box (q1 to q3)")
    assert_true('<line x1="123" y1="32" x2="123" y2="124"' in s, "A's median line (value 5), vertical across the box")
    assert_true('<rect x="236" y="147" width="48" height="92" fill="#1e64b4"/>' in s, "B's box (q1 to q3)")
    assert_true('<circle cx="365" cy="78" r="4" fill="#1e64b4"/>' in s, "A's single outlier, at value 20")


def test_box_horizontal_matches_plot_mark_box_horizontal() raises:
    # The quickplot box(horizontal=True) convenience function must
    # render identically to the fluent builder it wraps, and the
    # DType-generic overload must forward horizontal too (see
    # lollipop's own equivalent test -- a forwarding bug there was
    # caught this exact way).
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[2.0, 4.0, 7.0, 9.0], [10.0, 12.0, 15.0, 18.0]]
    var int_values: List[List[Int]] = [[2, 4, 7, 9], [10, 12, 15, 18]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = box(cats, values, theme=t, horizontal=True)
    var from_builder = Plot().mark_box(horizontal=True).encode_boxplot(cats, values).theme(t)
    var from_dtype = box(cats, int_values, theme=t, horizontal=True)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())
    assert_equal(render_svg(from_dtype).to_string(), render_svg(from_builder).to_string())


def test_render_horizontal_box_raises_on_mismatched_length() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var plot = box(cats, values, horizontal=True)
        _ = render_svg(plot)

# ---------------------------------------------------------------
# from tests/test_horizontal_grouped_bar.mojo
# ---------------------------------------------------------------

def test_render_svg_horizontal_grouped_bar_matches_hand_derived_rectangles_and_legend() raises:
    # 2 categories ("A"/"B"), 2 series -- values[0] (North) = [10, 20]
    # (North's value for A, then B), values[1] (South) = [5, 15]
    # (South's value for A, then B) -- the same data/mapping test_
    # grouped_bar.mojo's own hand-derived-rectangles test uses, so its
    # domain math ([0, 21], zero exact so unpadded) carries over
    # unchanged. Canvas 400x300, show_gridlines=False, show_legend at
    # its default (True) -- legend reserves 130px, so the frame's own
    # plot area is x:[60,250] y:[20,250] (the horizontal mirror of that
    # test's own [60,250]x-range/[20,250]y-range, both axes swapped).
    #
    # Every value here is non-negative, so the baseline (0) lands
    # exactly on the frame's left axis line (px0=60) -- every sub-bar's
    # left edge is pulled 1px to 61 (see _pull_off_axis_line's
    # docstring, plot.mojo). Category A's band starts at y=31.5,
    # bandwidth 92, sub_height 46 (2 series) -> North's row y:[32,78),
    # South's row y:[78,124). Category B's band starts at y=146.5 ->
    # North's row y:[147,193), South's row y:[193,239). Every position
    # independently re-derived via python3 and cross-checked against
    # the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = Plot().mark_grouped_bar(horizontal=True).encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<rect x="61" y="32" width="89" height="46" fill="#1f77b4"/>' in s, "A/North")
    assert_true('<rect x="61" y="78" width="44" height="46" fill="#ff7f0e"/>' in s, "A/South")
    assert_true('<rect x="61" y="147" width="180" height="46" fill="#1f77b4"/>' in s, "B/North")
    assert_true('<rect x="61" y="193" width="135" height="46" fill="#ff7f0e"/>' in s, "B/South")

    # Legend: same starting corner _render_horizontal_grouped_bar's own
    # docstring explains (frame.x_scale.range_max + margin_right,
    # frame.py0) -- x=230+20=250? actually resolves to 270 (see the
    # vertical Mark.GROUPED_BAR test's own identical 270,20 -- the
    # same legend width/margins on this same 400x300 canvas produce
    # the same corner regardless of orientation).
    assert_true('<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "North's legend swatch")
    assert_true('<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "South's legend swatch")


def test_render_svg_horizontal_grouped_bar_supports_show_data_labels_with_mixed_signs() raises:
    # values[0] (North) = [10, -5], values[1] (South) = [20, 15] --
    # mixed signs this time, so the baseline no longer lands on the
    # frame's own left axis line (unlike the sibling test above) and
    # no pull-off applies. Every position independently re-derived via
    # python3 and cross-checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, -5.0], [20.0, 15.0]]
    var plot = Plot().mark_grouped_bar(horizontal=True).encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False, show_data_labels=True)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<rect x="103" y="32" width="69" height="46" fill="#1f77b4"/>' in s, "A/North (10)")
    assert_true(
        '<text x="176" y="59" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="start">10</text>' in s,
        "A/North's label, right of its own bar, left-aligned",
    )
    assert_true('<rect x="69" y="147" width="34" height="46" fill="#1f77b4"/>' in s, "B/North (-5)")
    assert_true(
        '<text x="65" y="174" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="end">-5</text>' in s,
        "B/North's label, left of its own bar (negative), right-aligned",
    )


def test_grouped_bar_horizontal_matches_plot_mark_grouped_bar_horizontal() raises:
    # The quickplot grouped_bar(horizontal=True) convenience function
    # must render identically to the fluent builder it wraps, and the
    # DType-generic overload must forward horizontal too (see lollipop's
    # own equivalent test -- a forwarding bug there was caught this
    # exact way).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var int_values: List[List[Int]] = [[10, 20], [5, 15]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = grouped_bar(cats, names, values, theme=t, horizontal=True)
    var from_builder = Plot().mark_grouped_bar(horizontal=True).encode_grouped_bar(cats, names, values).theme(t)
    var from_dtype = grouped_bar(cats, names, int_values, theme=t, horizontal=True)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())
    assert_equal(render_svg(from_dtype).to_string(), render_svg(from_builder).to_string())


def test_render_horizontal_grouped_bar_zero_length_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    var plot = Plot().mark_grouped_bar(horizontal=True).encode_grouped_bar(cats, names, values).size(200, 150)
    var s = render_svg(plot).to_string()
    assert_true("<rect" in s, "still fills the background")
    assert_true("<line" not in s, "no axis lines drawn for zero categories")

# ---------------------------------------------------------------
# from tests/test_horizontal_lollipop.mojo
# ---------------------------------------------------------------

def test_render_svg_horizontal_lollipop_matches_hand_derived_positions() raises:
    # Same 2-category, values=[10,-5], 640x420-default-margins frame
    # test_horizontal_bar.mojo's own hand-derived-rectangles test uses
    # (plot area x:[60,620] y:[20,370], baseline pixel 255 -- the "0"
    # tick this same render confirms independently, since _zero_
    # baseline_y_extent's domain math is identical for both marks).
    # Row centers: band height (370-20)/2=175 -> A=20+87.5=107.5,
    # B=20+175+87.5=282.5. Stem A (10): 60+(10-(-5.75))/16.5*560=
    # 594.545 (rounds to 595 for the point). Stem B (-5): 60+(-5-
    # (-5.75))/16.5*560=85.455 (rounds to 85). Neither stem start
    # lands on px0=60, so no 1px pull-off applies here (see the
    # sibling test below for that case). Every position independently
    # re-derived via python3 and cross-checked against the actual
    # rendered SVG.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var plot = Plot().mark_lollipop(horizontal=True).encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<path d="M255.152,107.500 L594.545,107.500"' in s, "stem A, extending right from the baseline"
    )
    assert_true('<circle cx="595" cy="108" r="4" fill="#1e64b4"/>' in s, "point A, at its value")
    assert_true(
        '<path d="M255.152,282.500 L85.455,282.500"' in s, "stem B, extending left from the baseline"
    )
    assert_true('<circle cx="85" cy="283" r="4" fill="#1e64b4"/>' in s, "point B, at its value")
    assert_true('<text x="255" y="391"' in s and ">0</text>" in s, "the 0 tick lands where the baseline math predicts")


def test_render_horizontal_lollipop_pulls_off_axis_line_when_baseline_touches_left_edge() raises:
    # All-positive data -- the domain's low end stays exactly 0
    # (unpadded), so the baseline lands exactly on the frame's own
    # left axis line (px0=60) -- the stem start should nudge to 61,
    # the same hairline-of-background protection the vertical Mark.
    # LOLLIPOP path already gets at its own bottom edge, and the
    # horizontal Mark.BAR path gets at this same left edge.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = Plot().mark_lollipop(horizontal=True).encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<path d="M61.000,107.500 L326.667,107.500"' in s, "stem A pulled off the axis line"
    )
    assert_true(
        '<path d="M61.000,282.500 L593.333,282.500"' in s, "stem B pulled off the axis line"
    )


def test_lollipop_horizontal_matches_plot_mark_lollipop_horizontal() raises:
    # The quickplot lollipop(horizontal=True) convenience function must
    # render identically to the fluent builder it wraps -- the same
    # equivalence test_quickplot.mojo's own test_lollipop_matches_
    # manual_plot establishes for the vertical (default) case.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var t = Theme(show_gridlines=False)
    var from_quickplot = lollipop(cats, vals, theme=t, horizontal=True)
    var from_builder = Plot().mark_lollipop(horizontal=True).encode_categorical(x=cats, y=vals).theme(t)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())


def test_lollipop_dtype_generic_overload_forwards_horizontal() raises:
    # The DType-generic lollipop[dtype: DType](...) overload must
    # forward its own horizontal parameter to the concrete lollipop()
    # it delegates to -- caught missing once during development (the
    # signature gained the parameter before the forwarding call did,
    # silently ignoring it and always rendering vertical).
    var cats: List[String] = ["A", "B"]
    var vals: List[Int] = [10, -5]
    var float_vals: List[Float64] = [10.0, -5.0]
    var from_dtype = lollipop(cats, vals, horizontal=True)
    var from_concrete = lollipop(cats, float_vals, horizontal=True)
    assert_equal(render_svg(from_dtype).to_string(), render_svg(from_concrete).to_string())


def test_render_horizontal_lollipop_empty_data_only_fills_background() raises:
    var plot = Plot().mark_lollipop(horizontal=True).size(50, 40)  # no encode_categorical() call
    var s = render_svg(plot).to_string()
    assert_true("<rect" in s, "still fills the background")
    assert_true("<line" not in s, "no axis lines drawn for zero categories")

# ---------------------------------------------------------------
# from tests/test_horizontal_stacked_bar.mojo
# ---------------------------------------------------------------

def test_render_svg_horizontal_stacked_bar_matches_hand_derived_rectangles_and_legend() raises:
    # Same values[0]/values[1] = North=[10,20]/South=[5,15] as the
    # sibling horizontal grouped-bar test, but stacked: category A's
    # total is 15 (10+5), category B's is 35 (20+15) -- domain over
    # [pos_total, neg_total] per category = [15, 0, 35, 0] ->
    # _zero_baseline_y_extent -> [0, 36.75] (zero exact, so only the
    # high end padded 5%). Canvas 400x300, show_gridlines=False,
    # show_legend default (True), same [60,250]x[20,250] frame the
    # sibling grouped-bar test derives.
    #
    # Each category's row is the *full* band height (92, not split
    # into sub-rows) -- band_y(A)=32 (round(31.5)), band_y(B)=147
    # (round(146.5)), matching the sibling test's own band-start math.
    # North's segment always starts at the baseline (pulled 1px to 61,
    # non-negative-only domain -- see _pull_off_axis_line's docstring);
    # South's segment picks up exactly where North's left off (the
    # running-total property `_render_stacked_bar`'s own docstring
    # explains -- no extra rounding trick needed for that shared
    # edge). Every position independently re-derived via python3 and
    # cross-checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = Plot().mark_stacked_bar(horizontal=True).encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<rect x="61" y="32" width="51" height="92" fill="#1f77b4"/>' in s, "A/North")
    assert_true('<rect x="112" y="32" width="26" height="92" fill="#ff7f0e"/>' in s, "A/South, picks up where North left off")
    assert_true('<rect x="61" y="147" width="102" height="92" fill="#1f77b4"/>' in s, "B/North")
    assert_true('<rect x="163" y="147" width="78" height="92" fill="#ff7f0e"/>' in s, "B/South")

    assert_true('<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "North's legend swatch")
    assert_true('<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "South's legend swatch")


def test_render_svg_horizontal_stacked_bar_percent_fixes_x_axis_to_0_100() raises:
    # values[0] (North) = [10, 30], values[1] (South) = [20, 10] --
    # category A: North=10/South=20, total 30, scale_factor=100/30;
    # North -> 33.33% -> [0,33.33], South -> 66.67% -> [33.33,100].
    # Category B: North=30/South=10, total 40, scale_factor=100/40=2.5;
    # North -> 75% -> [0,75], South -> 25% -> [75,100]. The x-axis
    # itself is fixed to exactly [0,100] regardless of the raw data
    # (Plot.mark_stacked_bar()'s own docstring) -- confirmed here by
    # the "100" tick landing at the frame's own right edge (250), not
    # some data-dependent padded value. Every position independently
    # re-derived via python3 and cross-checked against the actual
    # rendered SVG.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 30.0], [20.0, 10.0]]
    var plot = Plot().mark_stacked_bar(percent=True, horizontal=True).encode_grouped_bar(
        cats, names, values
    ).theme(Theme(show_gridlines=False)).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<text x="250" y="271"' in s and ">100</text>" in s, "the x-axis is fixed to end at exactly 100")
    assert_true('<rect x="61" y="32" width="62" height="92" fill="#1f77b4"/>' in s, "A/North, 33.3% of A's total")
    assert_true('<rect x="123" y="32" width="127" height="92" fill="#ff7f0e"/>' in s, "A/South, the remaining 66.7%")
    assert_true('<rect x="61" y="147" width="142" height="92" fill="#1f77b4"/>' in s, "B/North, 75% of B's total")
    assert_true('<rect x="203" y="147" width="47" height="92" fill="#ff7f0e"/>' in s, "B/South, the remaining 25%")


def test_render_horizontal_stacked_bar_percent_raises_on_a_negative_value() raises:
    var cats: List[String] = ["A"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0], [-5.0]]
    with assert_raises():
        var plot = Plot().mark_stacked_bar(percent=True, horizontal=True).encode_grouped_bar(cats, names, values)
        _ = render_svg(plot)


def test_stacked_bar_horizontal_matches_plot_mark_stacked_bar_horizontal() raises:
    # The quickplot stacked_bar(horizontal=True) convenience function
    # must render identically to the fluent builder it wraps, and the
    # DType-generic overload must forward horizontal too (see
    # lollipop's own equivalent test -- a forwarding bug there was
    # caught this exact way).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var int_values: List[List[Int]] = [[10, 20], [5, 15]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = stacked_bar(cats, names, values, theme=t, horizontal=True)
    var from_builder = Plot().mark_stacked_bar(horizontal=True).encode_grouped_bar(cats, names, values).theme(t)
    var from_dtype = stacked_bar(cats, names, int_values, theme=t, horizontal=True)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())
    assert_equal(render_svg(from_dtype).to_string(), render_svg(from_builder).to_string())


def test_render_horizontal_stacked_bar_zero_length_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    var plot = Plot().mark_stacked_bar(horizontal=True).encode_grouped_bar(cats, names, values).size(200, 150)
    var s = render_svg(plot).to_string()
    assert_true("<rect" in s, "still fills the background")
    assert_true("<line" not in s, "no axis lines drawn for zero categories")

# ---------------------------------------------------------------
# from tests/test_horizontal_violin.mojo
# ---------------------------------------------------------------

def test_render_svg_horizontal_violin_matches_hand_derived_silhouette_points() raises:
    # 2 categories ("Section A"/"Section B", the same classes/scores
    # test_violin.mojo's own docstring example uses), canvas 400x300,
    # show_gridlines=False. The dynamic left margin grows to fit
    # "Section A"/"Section B" (longer than a single-letter category),
    # so the frame's own plot_x0 is 72, not the default 60 -- the same
    # kind of dynamic-margin growth `_draw_horizontal_categorical_axis_
    # frame`'s own docstring explains. Every KDE sample point is a
    # dense floating-point curve (Silverman's-rule bandwidth, computed
    # from each category's own std/n) -- rather than re-deriving all
    # 60 points per category by hand, this spot-checks the exact first
    # sampled point (the curve's own left edge, at each category's
    # own min(values)) of each category's closed path, independently
    # re-derived via python3 and cross-checked against the actual
    # rendered SVG.
    var cats: List[String] = ["Section A", "Section B"]
    var values: List[List[Float64]] = [
        [72.0, 75.0, 78.0, 80.0, 74.0, 76.0, 91.0],
        [65.0, 70.0, 72.0, 88.0, 90.0, 92.0, 95.0],
    ]
    var plot = Plot().mark_violin(horizontal=True).encode_distribution(categories=cats, values=values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<path d="M151.000,103.966' in s, "Section A's silhouette starts at its own min(values)=72")
    assert_true('<path d="M86.000,215.697' in s, "Section B's silhouette starts at its own min(values)=65")


def test_violin_horizontal_matches_plot_mark_violin_horizontal() raises:
    # The quickplot violin(horizontal=True) convenience function must
    # render identically to the fluent builder it wraps, and the
    # DType-generic overload must forward horizontal too (see
    # lollipop's own equivalent test -- a forwarding bug there was
    # caught this exact way).
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[72.0, 75.0, 78.0, 80.0], [65.0, 70.0, 88.0, 90.0]]
    var int_values: List[List[Int]] = [[72, 75, 78, 80], [65, 70, 88, 90]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = violin(cats, values, theme=t, horizontal=True)
    var from_builder = Plot().mark_violin(horizontal=True).encode_distribution(categories=cats, values=values).theme(t)
    var from_dtype = violin(cats, int_values, theme=t, horizontal=True)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())
    assert_equal(render_svg(from_dtype).to_string(), render_svg(from_builder).to_string())


def test_violin_horizontal_accepts_bandwidth_and_scale_by_count() raises:
    # bandwidth/scale_by_count are orientation-independent overrides --
    # this just confirms they still apply (don't get silently dropped)
    # when combined with horizontal=True, without re-deriving the
    # resulting curve by hand.
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[72.0, 75.0, 78.0, 80.0], [65.0, 70.0, 88.0, 90.0, 92.0]]
    var plot = Plot().mark_violin(bandwidth=5.0, scale_by_count=True, horizontal=True).encode_distribution(
        categories=cats, values=values
    )
    var s = render_svg(plot).to_string()
    assert_true("<path" in s, "still renders a silhouette with bandwidth/scale_by_count overrides")


def test_render_horizontal_violin_raises_on_negative_bandwidth() raises:
    var cats: List[String] = ["A"]
    var values: List[List[Float64]] = [[1.0, 2.0, 3.0]]
    with assert_raises():
        var plot = Plot().mark_violin(bandwidth=-1.0, horizontal=True).encode_distribution(
            categories=cats, values=values
        )
        _ = render_svg(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
