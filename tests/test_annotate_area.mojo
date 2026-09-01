"""Tests for Plot.annotate_area(): shaded reference-band placement
(SVG + a raster ink companion), the mark-support boundary (mirroring
annotate_line()'s), an out-of-range band drawing nothing, a
partially-out-of-range band clipping to the visible portion instead of
disappearing, and multiple bands stacking via repeated calls.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme

from _test_helpers import _assert_color, _assert_near_color


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
