"""Tests for Plot.annotate_band(): a filled region between two curves
(unlike annotate_area()'s constant (y0, y1) pair) -- hand-derived (via
a real render, cross-checked by hand) path/label placement, the
length-mismatch raise, the y_upper < y_lower raise, the mark-support
boundary (mirroring annotate_point()'s), and clamped-not-crashing
behavior when a band's x/y overshoot the mark's own domain.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme

from _test_helpers import _assert_color


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
    # Raster-side companion -- confirms canvas_mojo.fill_path_aa
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
