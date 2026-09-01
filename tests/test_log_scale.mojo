"""Tests for Plot.scale_y_log()/scale_x_log(): the log10-scaled axis
support built on top of LinearScale's own is_log field (see scale.mojo
and its own test_scale.mojo tests for the pure tick/to_pixel math this
builds on) -- correct pixel placement of real data through the shared
to_pixel() path, and every raise path (non-positive data, an
incompatible mark, Mark.AREA specifically, a non-positive annotation
value, and render_layers()'s own rejection).
"""

from std.testing import assert_raises, assert_true, TestSuite

from dataviz.plot import Plot, render, render_svg, render_layers, save_layers


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
