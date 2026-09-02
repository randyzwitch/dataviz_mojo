"""Tests for `Plot.mark_lollipop(horizontal=True)`/`lollipop(...,
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
"""

from std.testing import assert_equal, assert_true, TestSuite

from dataviz.plot import Plot, render_svg
from dataviz.theme import Theme
from dataviz import lollipop


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
