"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_error_bars.mojo`: Tests for Plot.encode()'s y_err channel: symmetric error-bar
  whiskers on Mark.POINT/EFFECT_SCATTER, drawn in each point's own
  resolved color (see encode()'s own docstring). Hand-derived pixel
  positions for the whisker/cap placement, the y-domain correctly
  widening to include each whisker's own endpoint (not just the raw
  point), and every raise path (negative y_err, a length mismatch, and
  y_err on an incompatible mark).

- `test_error_bars_asymmetric.mojo`: Tests for Plot.encode()'s y_err_lower/y_err_upper channels: an
  asymmetric error-bar whisker, mutually exclusive with the existing
  symmetric y_err (#140), given together or not at all. Hand-derived
  pixel positions confirming the whisker is genuinely asymmetric (not
  silently falling back to a symmetric one), the y-domain widening to
  each bound's own endpoint, and every raise path.

- `test_error_bars_on_line.mojo`: Tests for Plot.encode(y_err=...) on Mark.LINE (#140 was Mark.POINT/
  EFFECT_SCATTER only): a whisker per original data point, drawn in
  Theme.mark_color (Mark.LINE has no per-point color the way Mark.POINT's
  color/color_categories channels do), independent of _draw_line_layer's
  own point-decimation for the stroked path. Hand-derived pixel positions
  and confirmation Mark.AREA (still excluded) raises.

- `test_log_scale.mojo`: Tests for Plot.scale_y_log()/scale_x_log(): the log10-scaled axis
  support built on top of LinearScale's own is_log field (see scale.mojo
  and its own test_scale.mojo tests for the pure tick/to_pixel math this
  builds on) -- correct pixel placement of real data through the shared
  to_pixel() path, and every raise path (non-positive data, an
  incompatible mark, Mark.AREA specifically, a non-positive annotation
  value, and render_layers()'s own rejection).

- `test_data_labels.mojo`: Tests for Theme.show_data_labels on Mark.BAR/GROUPED_BAR/STACKED_BAR:
  each bar/sub-bar/segment's own value drawn as text -- hand-derived
  (cross-checked against a real render) label placement and formatting
  for all three marks, the above-positive/below-negative placement for
  BAR/GROUPED_BAR, centered-inside placement for STACKED_BAR, real-value
  (not axis-tick-rounded) decimal formatting, and the default-off case.

- `test_point_labels.mojo`: Tests for `Plot.encode()`'s `labels` channel on `Mark.POINT`/
  `EFFECT_SCATTER`: each point's own text drawn centered directly above
  it -- hand-derived (cross-checked against a real render) label
  placement, the per-row `""` opt-out, the default-no-labels case, and
  every raise path (a length mismatch, an unsupported mark).

- `test_color_map.mojo`: Tests for Plot.encode()'s color_map channel: pinning a specific
  color_categories value to a specific color, unmapped categories keeping
  their ordinary first-seen-order palette color, the override reaching
  both the point itself and its legend swatch (both read the same
  resolved _PointChannels.palette), and the one raise path (color_map
  given with color_categories empty).

"""

from canvas.color import Color
from dataviz.colors import TOMATO
from dataviz.plot import Plot, render, render_layers, render_svg, save_layers
from dataviz.theme import Theme
from std.collections import Dict
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_error_bars.mojo
# ---------------------------------------------------------------

def test_render_svg_error_bar_matches_hand_derived_positions() raises:
    # One point, x=1, y=10, y_err=2 -- domain data becomes [8, 12]
    # (_data_extent's own "everything actually drawn" rule -- see
    # _render_generic's y_domain_data comment), padded 5% of that span
    # (4.0) -> domain [7.8, 12.2]. Canvas 400x200, default theme -> plot_y0 = margin_top (20), plot_y1 = height - margin_bottom
    # (200-50=150).
    #
    # scale() = (20-150)/(12.2-7.8) = -130/4.4 = -29.5454...
    # translate() = 150 - 7.8*scale() = 380.4545...
    # to_pixel(8.0)  (bottom whisker end) = 144.0909... -> rounds to 144
    # to_pixel(12.0) (top whisker end)    = 25.909...   -> rounds to 26
    # to_pixel(10.0) (the point itself)   = 85.0 exactly
    #
    # Asserted as `cy="..."`/`y1="..."`/`y2="..."` substrings, not full
    # tags -- `cx`/`x1`/`x2` depend on the dynamic left margin (sized
    # off the y-tick label text width), unrelated to this test's own
    # subject and already covered by every other continuous-axis test.
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [10.0]
    var err: List[Float64] = [2.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err).size(400, 200)
    var s = render_svg(plot).to_string()
    assert_true('cy="85"' in s, "the point itself lands at the hand-derived pixel row")
    assert_true('y1="144"' in s and 'y2="144"' in s, "the bottom whisker/cap sits at y-2's hand-derived row")
    assert_true('y1="26"' in s and 'y2="26"' in s, "the top whisker/cap sits at y+2's hand-derived row")


def test_render_svg_error_bar_uses_the_points_own_resolved_color() raises:
    # Two categories, two distinct palette colors -- the error bar's
    # own stroke color must match each point's own resolved color
    # (ch.palette[...]), not a fixed Theme color.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var cats: List[String] = ["a", "b"]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err, color_categories=cats).size(400, 300)
    var s = render_svg(plot).to_string()
    assert_true('stroke="#1f77b4"' in s, "the first category's own palette color, reused for its error bar")
    assert_true('stroke="#ff7f0e"' in s, "the second category's own palette color, reused for its error bar")


def test_render_widens_the_y_domain_to_include_the_whisker_extent() raises:
    # y=[10], y_err=[20] -- the whisker reaches down to -10, well
    # outside plot.y_data's own [10, 10] range. Domain data becomes
    # [-10, 30], padded 5% of that span (2.0) -> [-12, 32] ->
    # _nice_step picks a step of 10 -> ticks [-10, 0, 10, 20, 30]
    # (independently hand-derived, same algorithm test_scale.mojo's
    # own _nice_step tests already verify). If the y-domain were
    # computed from plot.y_data alone (not widened for y_err), no
    # negative tick would ever appear -- plot.y_data is a single
    # constant 10.0, nowhere near zero.
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [10.0]
    var err: List[Float64] = [20.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err).size(400, 300)
    var s = render_svg(plot).to_string()
    assert_true(">-10<" in s, "a negative-valued y tick, only reachable if the domain widened for y_err")


def test_render_raises_on_a_negative_y_err_value() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, -1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_y_err_length_mismatch() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 20.0, 30.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_y_err_with_an_incompatible_mark() raises:
    # Mark.AREA -- still excluded (see tests/test_error_bars_on_line.
    # mojo's own docstring for why, and its own dedicated test for this
    # exact case). Mark.LINE was the incompatible mark this test used
    # to check, before #146 added y_err support there deliberately.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_area().encode(x=x, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)

# ---------------------------------------------------------------
# from tests/test_error_bars_asymmetric.mojo
# ---------------------------------------------------------------

def test_render_svg_asymmetric_error_bar_matches_hand_derived_positions() raises:
    # One point, x=1, y=10, y_err_lower=2, y_err_upper=6 -- a genuinely
    # asymmetric whisker from 8 to 16 (not a symmetric +/-4 or +/-2).
    # Domain data becomes [8, 16] (widened to the whisker's own
    # endpoints, same "everything actually drawn" rule the symmetric
    # case already has), span 8, padded 5% (0.4) -> domain [7.6, 16.4].
    # Canvas 400x200, default theme -> plot_y0 = margin_top (20),
    # plot_y1 = height - margin_bottom (200-50=150).
    #
    # scale() = (20-150)/(16.4-7.6) = -130/8.8 = -14.7727...
    # translate() = 150 - 7.6*scale() = 262.2727...
    # to_pixel(8)  (bottom, y - y_err_lower) = 144.0909... -> rounds to 144
    # to_pixel(16) (top, y + y_err_upper)    = 25.909...   -> rounds to 26
    # to_pixel(10) (the point itself)        = 114.545...  -> rounds to 115
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [10.0]
    var lower: List[Float64] = [2.0]
    var upper: List[Float64] = [6.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper).size(400, 200)
    var s = render_svg(plot).to_string()
    assert_true('cy="115"' in s, "the point itself lands at the hand-derived pixel row")
    assert_true('y1="144"' in s and 'y2="144"' in s, "the lower whisker/cap sits at y-2's hand-derived row")
    assert_true('y1="26"' in s and 'y2="26"' in s, "the upper whisker/cap sits at y+6's hand-derived row")


def test_render_raises_when_only_y_err_lower_is_given() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var lower: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err_lower=lower)
    with assert_raises():
        _ = render(plot)


def test_render_raises_when_only_y_err_upper_is_given() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err_upper=upper)
    with assert_raises():
        _ = render(plot)


def test_render_raises_when_y_err_and_asymmetric_bounds_are_both_given() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var sym: List[Float64] = [1.0, 1.0]
    var lower: List[Float64] = [1.0, 1.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=sym, y_err_lower=lower, y_err_upper=upper)
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_negative_asymmetric_value() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var lower: List[Float64] = [1.0, -1.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper)
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_asymmetric_bounds_with_an_incompatible_mark() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var lower: List[Float64] = [1.0, 1.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_line().encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper)
    with assert_raises():
        _ = render(plot)

# ---------------------------------------------------------------
# from tests/test_error_bars_on_line.mojo
# ---------------------------------------------------------------

def test_render_svg_line_error_bar_matches_hand_derived_positions() raises:
    # Two points, x=[1,2], y=[10,10], y_err=[2,2] -- domain data becomes
    # [8, 12] (widened to the whisker endpoints), span 4, padded 5%
    # (0.2) -> domain [7.8, 12.2]. Canvas 400x200, default theme ->
    # plot_y0 = margin_top (20), plot_y1 = height - margin_bottom
    # (200-50=150).
    #
    # scale() = (20-150)/(12.2-7.8) = -130/4.4 = -29.5454...
    # translate() = 150 - 7.8*scale() = 380.4545...
    # to_pixel(8)  (bottom whisker end) = 144.09... -> rounds to 144
    # to_pixel(12) (top whisker end)    = 25.909...  -> rounds to 26
    # to_pixel(10) (the line itself, both points)    = 85.0 exactly
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 10.0]
    var err: List[Float64] = [2.0, 2.0]
    var plot = Plot().mark_line().encode(x=x, y=y, y_err=err).size(400, 200)
    var s = render_svg(plot).to_string()
    assert_true('y1="144"' in s and 'y2="144"' in s, "the bottom whisker/cap sits at y-2's hand-derived row")
    assert_true('y1="26"' in s and 'y2="26"' in s, "the top whisker/cap sits at y+2's hand-derived row")
    assert_true('85.000' in s, "the line itself passes through y=10's own row (85)")


def test_render_svg_line_error_bar_uses_theme_mark_color() raises:
    # Mark.LINE has no per-point color channel -- every whisker must
    # use the plain Theme.mark_color, the same ink the line strokes
    # with, not a fixed default unrelated to the chart's own color.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_line().encode(x=x, y=y, y_err=err).theme(Theme(mark_color=TOMATO))
    var s = render_svg(plot).to_string()
    assert_true('stroke="#ff6347"' in s, "the whisker uses the chart's own Theme.mark_color")


def test_render_raises_on_y_err_with_mark_area() raises:
    # Mark.AREA stays excluded (its own zero-baseline forcing is a
    # separate concern from this issue, not addressed here).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_area().encode(x=x, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)

# ---------------------------------------------------------------
# from tests/test_log_scale.mojo
# ---------------------------------------------------------------

def test_render_svg_scale_y_log_matches_hand_derived_positions() raises:
    # y = [1, 10, 100] -- three decades. _log_data_extent pads 5% of
    # the log-space span (log10(1)=0, log10(100)=2, span=2, pad=0.1)
    # -> domain [-0.1, 2.1]. Canvas 400x300, default theme (no legend,
    # no x_title/y_title) -> plot_y0 = margin_top (20), plot_y1 =
    # height - margin_bottom (300-50=250), matching test_secondary_
    # axis.mojo's own already-verified y:[20,250] geometry for the
    # identical canvas size/theme.
    #
    # scale() = (20-250)/(2.1-(-0.1)) = -230/2.2 = -104.5454...
    # translate() = 250 - (-0.1)*scale() = 239.5454...
    # to_pixel(1)  = log10(1)=0   -> 239.5454... -> rounds to 240
    # to_pixel(10) = log10(10)=1  -> 135.0 exactly
    # to_pixel(100)= log10(100)=2 -> 30.4545... -> rounds to 30
    #
    # Asserted as a `cy="..."` substring, not a full `<circle .../>`
    # tag -- `cx` depends on the dynamic left margin (sized off the
    # y-tick *label* text width), unrelated to this test's own subject
    # (the y-axis's log mapping) and already covered by every other
    # continuous-axis test that doesn't touch scale_y_log() at all.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 10.0, 100.0]
    var plot = Plot().mark_point().encode(x=x, y=y).size(400, 300).scale_y_log()
    var s = render_svg(plot).to_string()
    assert_true('cy="240"' in s, "y=1 lands at the hand-derived pixel row")
    assert_true('cy="135"' in s, "y=10 lands exactly one decade up (equal pixel gap to y=1's row)")
    assert_true('cy="30"' in s, "y=100 lands exactly one more decade up (the same pixel gap again)")


def test_render_raises_on_a_non_positive_value_with_scale_y_log() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 0.0, 5.0]
    var plot = Plot().mark_line().encode(x=x, y=y).scale_y_log()
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_negative_value_with_scale_x_log() raises:
    var x: List[Float64] = [1.0, -2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var plot = Plot().mark_line().encode(x=x, y=y).scale_x_log()
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_scale_y_log_with_mark_area() raises:
    # Mark.AREA's y-domain is always forced through a zero baseline
    # (_zero_baseline_y_extent) -- zero has no logarithm, so this
    # combination is rejected outright rather than silently producing
    # a degenerate/incorrect axis.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 10.0, 100.0]
    var plot = Plot().mark_area().encode(x=x, y=y).scale_y_log()
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_scale_y_log_with_an_incompatible_mark() raises:
    var categories: List[String] = ["a", "b", "c"]
    var values: List[Float64] = [1.0, 2.0, 3.0]
    var plot = Plot().mark_bar().encode_categorical(x=categories, y=values).scale_y_log()
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_non_positive_annotate_line_value_with_scale_y_log() raises:
    # An annotation is drawn through the identical to_pixel() call the
    # data points use -- a non-positive value has the same "no honest
    # pixel position" problem the data's own values are checked for.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 10.0, 100.0]
    var plot = Plot().mark_line().encode(x=x, y=y).scale_y_log().annotate_line(-5.0)
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_non_positive_annotate_vline_value_with_scale_x_log() raises:
    var x: List[Float64] = [1.0, 10.0, 100.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var plot = Plot().mark_line().encode(x=x, y=y).scale_x_log().annotate_vline(0.0)
    with assert_raises():
        _ = render(plot)


def test_render_layers_raises_on_a_layer_with_scale_y_log() raises:
    # render_layers() combines every layer's data into one shared
    # linear domain (combined_y) -- no log-space equivalent built yet,
    # so a log-scaled layer is rejected rather than silently combined
    # incorrectly.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 10.0]
    var a = Plot().mark_line().encode(x=x, y=y).scale_y_log()
    var b = Plot().mark_line().encode(x=x, y=y)
    var plots: List[Plot] = [a^, b^]
    with assert_raises():
        _ = render_layers(plots)

# ---------------------------------------------------------------
# from tests/test_data_labels.mojo
# ---------------------------------------------------------------

def test_render_svg_bar_data_labels_match_hand_derived_positions() raises:
    # 2 categories, y=[10.0, -5.5] -- canvas 400x300, no gridlines,
    # plot rect x:[60,380] y:[20,250] (this package's usual default-
    # margin frame for this size). band_start(A)=76, band_start(B)=236,
    # bandwidth=128 (OrdinalScale's usual 0.2-padding split for 2
    # categories over range [60,380]).
    #
    # A (10.0, positive): rect y=30, height=135 -> top edge at 30.
    #   label baseline = 30 - label_gap(4) = 26, centered at
    #   bar_x + bar_width//2 = 76+64 = 140.
    # B (-5.5, negative): rect y=165, height=75 -> bottom edge at 240.
    #   label baseline = 240 + label_gap(4) + font_size(12) = 256,
    #   centered at 236+64 = 300. "-5.5" keeps its real decimal --
    #   _label_decimals(-5.5) is 1, independent of whatever the
    #   y-axis's own tick labels (-5/0/5/10, all integers) use.
    # Every position independently re-derived via python3 and cross-
    # checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.5]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False, show_data_labels=True)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="140" y="26" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>' in s,
        "A's label, above the positive bar",
    )
    assert_true(
        '<text x="300" y="256" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>' in s,
        "B's label, below the negative bar, real decimal kept",
    )


def test_render_svg_bar_draws_no_labels_by_default() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.5]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('text-anchor="middle">10</text>' not in s, "no value label without show_data_labels=True")


def test_render_svg_grouped_bar_data_labels_match_hand_derived_positions() raises:
    # Same 2-category frame as the BAR test above; 2 series (North/
    # South) split each 128px band into two 64px sub-bars.
    # A: North=10 -> rect x=76,y=30,h=135, label at (76+32=108, 26).
    #    South=4 -> rect x=140,y=111,h=54, label at (140+32=172, 107).
    # B: North=-5.5 -> rect x=236,y=165,h=75, label at (236+32=268, 256).
    #    South=8 -> rect x=300,y=57,h=108, label at (300+32=332, 53).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, -5.5], [4.0, 8.0]]
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(
        categories=cats, series_names=names, values=values
    ).theme(Theme(show_gridlines=False, show_data_labels=True, show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<text x="108" y="26" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>' in s, "A/North's label")
    assert_true('<text x="172" y="107" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">4</text>' in s, "A/South's label")
    assert_true('<text x="268" y="256" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>' in s, "B/North's label, below its negative sub-bar")
    assert_true('<text x="332" y="53" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">8</text>' in s, "B/South's label")


def test_render_svg_stacked_bar_data_labels_match_hand_derived_positions() raises:
    # Same 2-category frame, same North/South data -- each segment's
    # label centers *inside* its own rect (vertically centered via
    # this package's usual font_size*0.35 baseline-centering offset,
    # e.g. treemap.mojo/sankey.mojo's own leaf/node labels), not
    # above/below the way BAR/GROUPED_BAR's labels sit.
    # A: North=10 (bottom segment) -> rect y=73,h=108 -> center
    #    73+54=127, +Int(12*0.35)=4 -> 131, at x=76+64=140.
    #    South=4 (stacked on top) -> rect y=30,h=43 -> center 30+21=51,
    #    +4 -> 55, at x=140.
    # B: North=-5.5 (negative, its own independent running total) ->
    #    rect y=181,h=59 -> center 181+29=210, +4 -> 214, at x=236+64=300.
    #    South=8 (positive, unrelated to North's negative stack) ->
    #    rect y=95,h=86 -> center 95+43=138, +4 -> 142, at x=300.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, -5.5], [4.0, 8.0]]
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(
        categories=cats, series_names=names, values=values
    ).theme(Theme(show_gridlines=False, show_data_labels=True, show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<text x="140" y="131" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>' in s, "A/North's label, centered inside its segment")
    assert_true('<text x="140" y="55" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">4</text>' in s, "A/South's label, centered inside its segment")
    assert_true('<text x="300" y="214" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>' in s, "B/North's label, its own segment value, not a cumulative total")
    assert_true('<text x="300" y="142" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">8</text>' in s, "B/South's label")

# ---------------------------------------------------------------
# from tests/test_point_labels.mojo
# ---------------------------------------------------------------

def test_render_svg_point_labels_match_hand_derived_positions() raises:
    # x=[1,2,3], y=[10,20,30], canvas 400x300, default theme (this
    # package's usual default-margin frame for this size) -- plot rect
    # x:[60,380] y:[20,250]. Points at (75,240), (220,135), (365,30)
    # (this package's usual 5%-padded LinearScale domain for this
    # data/range). labels=["a", "", "c"]: "b" deliberately omitted (the
    # per-row "" opt-out) to prove it draws no label for that one point
    # while its neighbors still get theirs.
    #
    # Label baseline sits label_gap(4) above the point's own top edge
    # (py - radius(4) - 4): "a" at (75, 240-4-4=232), "c" at
    # (365, 30-4-4=22).
    # Every position independently re-derived via python3 and cross-
    # checked against the actual rendered SVG.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 20.0, 30.0]
    var labels: List[String] = ["a", "", "c"]
    var plot = Plot().mark_point().encode(x=x, y=y, labels=labels).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="75" y="232" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">a</text>' in s,
        "first point's label",
    )
    assert_true(
        '<text x="365" y="22" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">c</text>' in s,
        "third point's label",
    )
    assert_true('>b<' not in s, "the middle point's \"\" entry draws no label at all")


def test_render_svg_point_draws_no_labels_by_default() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 20.0, 30.0]
    var plot = Plot().mark_point().encode(x=x, y=y).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('text-anchor="middle">a</text>' not in s, "no point labels without encode()'s labels")


def test_render_svg_effect_scatter_supports_labels() raises:
    # Same frame convention as the Mark.POINT test above, 2 points --
    # EFFECT_SCATTER's extra halo circle doesn't change the label's own
    # placement, which still anchors off the inner point circle's
    # radius, not the halo's.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var labels: List[String] = ["p", "q"]
    var plot = Plot().mark_effect_scatter().encode(x=x, y=y, labels=labels).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="75" y="232" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">p</text>' in s,
        "first point's label",
    )
    assert_true(
        '<text x="365" y="22" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">q</text>' in s,
        "second point's label",
    )


def test_encode_raises_on_labels_length_mismatch() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var labels: List[String] = ["only one"]
    with assert_raises():
        var plot = Plot().mark_point().encode(x=x, y=y, labels=labels).size(400, 300)
        _ = render_svg(plot)


def test_encode_raises_on_labels_with_an_unsupported_mark() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var labels: List[String] = ["a", "b"]
    with assert_raises():
        var plot = Plot().mark_line().encode(x=x, y=y, labels=labels).size(400, 300)
        _ = render_svg(plot)

# ---------------------------------------------------------------
# from tests/test_color_map.mojo
# ---------------------------------------------------------------

def test_render_svg_color_map_overrides_the_named_category() raises:
    # Two categories, "b" pinned to crimson (#dc143c) -- "a" must keep
    # its ordinary first-seen-order palette color (#1f77b4, tab10's
    # first blue), not shift because a later category got pinned.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var overrides: Dict[String, Color] = {"b": Color(220, 20, 60)}
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats, color_map=overrides)
    var s = render_svg(plot).to_string()
    assert_true('fill="#1f77b4"' in s, "unmapped category 'a' keeps its ordinary palette color")
    assert_true('fill="#dc143c"' in s, "mapped category 'b' uses the overridden color")
    assert_true('fill="#ff7f0e"' not in s, "'b' must not also show its ordinary (unoverridden) color")


def test_render_svg_color_map_override_reaches_the_legend_swatch_too() raises:
    # The legend swatch for the overridden category must show the same
    # overridden color, not the ordinary palette one -- both the point
    # and the swatch read the same resolved _PointChannels.palette.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var overrides: Dict[String, Color] = {"b": Color(220, 20, 60)}
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats, color_map=overrides)
    var s = render_svg(plot).to_string()
    assert_true('<rect x="' in s and 'fill="#dc143c"' in s, "a legend swatch uses the overridden color")


def test_render_svg_color_map_leaves_an_unrelated_column_of_the_same_name_alone() raises:
    # A color_map key that never appears among the actual categories is
    # not an error -- confirmed by rendering successfully with a
    # harmless extra key.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var overrides: Dict[String, Color] = {"c": Color(0, 0, 0)}
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats, color_map=overrides)
    _ = render_svg(plot)


def test_render_raises_on_color_map_without_color_categories() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var overrides: Dict[String, Color] = {"a": Color(0, 0, 0)}
    var plot = Plot().mark_point().encode(x=x, y=y, color_map=overrides)
    with assert_raises():
        _ = render(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
