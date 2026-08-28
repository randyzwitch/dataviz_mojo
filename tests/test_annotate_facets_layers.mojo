"""Tests for Plot.annotate_line()/annotate_area() wired into
render_facets()/render_layers(): each facet cell's annotations draw
against that cell's independent y-scale, and each layer's annotations draw against that layer's y-scale (primary or
secondary), not some other cell's/layer's.
"""

from std.testing import assert_true, TestSuite

from dataviz_mojo.plot import Plot, render_facets_svg, render_layers_svg
from dataviz_mojo.theme import Theme


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
