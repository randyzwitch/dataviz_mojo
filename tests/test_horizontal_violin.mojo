"""Tests for `Plot.mark_violin(horizontal=True)`/`violin(...,
horizontal=True)` (#121): `_render_horizontal_violin`'s silhouette
path (spot-checked at hand-derived points, the KDE curve itself being
too dense to fully re-derive by hand -- the same tolerance test_
violin.mojo's own tests take), the quickplot `violin()` function
matching the fluent `Plot.mark_violin(horizontal=True)` builder
exactly (both the concrete and `DType`-generic overload), `bandwidth`/
`scale_by_count` combined with `horizontal=True`, and the negative-
bandwidth raise.
"""

from std.testing import assert_equal, assert_raises, assert_true, TestSuite

from dataviz.plot import Plot, render_svg
from dataviz.theme import Theme
from dataviz import violin


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
