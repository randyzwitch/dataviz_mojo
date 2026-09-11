"""Tests for the color keys on the contour, tricontour and tripcolor
marks (#525).

`Mark.CONTOUR` and `Mark.CONTOURF` built a `ColorScale` and painted with
it while drawing no key at all, so the chart showed colors the reader had
nothing to read them against. The discriminator used throughout is the
count of `<text>` elements with the legend on against off: the axis
furniture is identical either way, so the difference is exactly the
key's rows.

`Mark.TRICONTOUR`, `TRICONTOURF` and `TRIPCOLOR` have the same gap and
are not covered here; they are layerable, and a standalone key without a
layered one breaks the invariant that a lone layer matches the
standalone chart. See #525.
"""

from std.math import cos, sin
from std.testing import TestSuite, assert_equal, assert_true

from _test_helpers import _attr_values, _count_tag
from dataviz import contour, contourf
from dataviz.plot import Plot, render_svg
from dataviz.theme import Theme


def _grid() -> List[List[Float64]]:
    var z = List[List[Float64]]()
    for r in range(16):
        var row = List[Float64]()
        for c in range(20):
            row.append(sin(Float64(c) / 5.0) * cos(Float64(r) / 4.0) * 10.0)
        z.append(row^)
    return z^


def _texts(p: Plot) raises -> Int:
    return _count_tag(render_svg(p).to_string(), "text")


def _on() -> Theme:
    return Theme(show_gridlines=False)


def _off() -> Theme:
    return Theme(show_gridlines=False, show_legend=False)


def test_both_contour_marks_draw_a_key_they_previously_did_not() raises:
    # The axis furniture is the same either way, so the delta is the
    # key. Before #525 each of these was zero.
    var z = _grid()
    var levels = 5

    var d_contour = _texts(
        contour(z, level_count=levels, theme=_on(), width=460, height=320)
    ) - _texts(
        contour(z, level_count=levels, theme=_off(), width=460, height=320)
    )
    var d_contourf = _texts(
        contourf(z, level_count=levels, theme=_on(), width=460, height=320)
    ) - _texts(
        contourf(z, level_count=levels, theme=_off(), width=460, height=320)
    )
    # One row per level: the levels are discrete by construction, so the
    # key is a swatch each rather than a gradient bar.
    assert_equal(d_contour, levels, "contour draws one key row per level")
    assert_equal(d_contourf, levels, "contourf draws one key row per level")


def test_the_key_rows_are_ordered_high_to_low() raises:
    # The *values* descend, not merely the row positions -- rows always
    # run down the page whatever order they were handed in, so asserting
    # their y-coordinates proves nothing. This reads the labels.
    var s = render_svg(
        contourf(_grid(), level_count=4, theme=_on(), width=460, height=320)
    ).to_string()
    var labels = List[String]()
    var at = s.find("<text")
    while at >= 0:
        var gt = s.find(">", at)
        var close = s.find("</text>", gt)
        labels.append(String(s[byte = gt + 1 : close]))
        at = s.find("<text", at + 1)
    assert_true(len(labels) >= 4, "the key drew rows")
    # The key's rows are the last four text elements.
    var n = len(labels)
    var previous = Float64(labels[n - 4])
    for i in range(n - 3, n):
        var value = Float64(labels[i])
        assert_true(
            value < previous,
            "key rows descend in value -- got "
            + labels[i]
            + " after "
            + labels[i - 1],
        )
        previous = value


def test_a_key_swatch_is_the_color_of_the_band_it_keys() raises:
    # The invariant that makes the key worth drawing, and the one that
    # catches a key built from the data's own limits while the bands
    # honor a `scale_color_domain()` override: every swatch color must
    # be a color actually painted on the chart.
    var pinned = render_svg(
        contourf(_grid(), level_count=4, theme=_on(), width=460, height=320)
        ^.scale_color_domain(-40.0, 40.0)
    ).to_string()
    var band_fills = _attr_values(pinned, "path", "fill")
    var swatch_fills = _attr_values(pinned, "rect", "fill")
    assert_true(len(band_fills) > 0, "the bands drew")
    # The key's swatches are the last four rects: the key is drawn after
    # the chart. The others are the background and the plot area, which
    # can share a fill with a band by coincidence.
    assert_true(len(swatch_fills) >= 4, "the key drew swatches")
    var matched = 0
    for i in range(len(swatch_fills) - 4, len(swatch_fills)):
        for band in band_fills:
            if swatch_fills[i] == band:
                matched += 1
                break
    assert_equal(
        matched,
        4,
        "each of the four swatches is a color the chart paints -- got "
        + String(matched)
        + " of 4",
    )


def test_turning_the_legend_off_removes_the_key_entirely() raises:
    var z = _grid()
    var s = render_svg(
        contourf(z, level_count=5, theme=_off(), width=460, height=320)
    ).to_string()
    var on = render_svg(
        contourf(z, level_count=5, theme=_on(), width=460, height=320)
    ).to_string()
    assert_true(
        _count_tag(on, "rect") > _count_tag(s, "rect"),
        "the key's swatches are rects, and they go with the legend",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
