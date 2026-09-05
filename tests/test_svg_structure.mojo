"""Structural SVG assertions (#219).

The SVG tests elsewhere assert on `to_string()` substrings. That catches
gross breakage but not structure: a mark emitting its rects outside the
annotated tooltip group, an unclosed `<g>`, or a legend drawing the right
colours the wrong number of times all pass a substring check.

These count elements, read attributes per element type, and pull the
`<title>` out of annotated groups (`_test_helpers.mojo`), so an assertion
can say "N bars produce exactly N `<rect>`s, in these N colours" rather
than "this colour appears somewhere".

Every case here also runs the well-formedness check, since it is free
once a document has been rendered.

One thing to know before reading the counts: canvas emits a background
`<rect>` covering the whole canvas as the document's first element, so a
chart with four bars has five rects. The counts below name that
explicitly rather than quietly adding one, since a reader checking the
arithmetic against a rendered file needs to know where the extra came
from.
"""

from _test_helpers import (
    _assert_well_formed_svg,
    _attr_values,
    _count_tag,
    _group_titles,
)
from dataviz import bar, box, grouped_bar, pie, scatter
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import Plot, render_svg
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_true


def _cats() -> List[String]:
    return ["a", "b", "c", "d"]


def _vals() -> List[Float64]:
    return [4.0, 1.0, 3.0, 2.0]


def test_bars_produce_one_rect_each_in_the_mark_colour() raises:
    """Four bars are four `<rect>`s in `Theme.mark_color`, after the
    document's background rect -- not "the colour appears somewhere",
    which one bar would satisfy just as well.

    Gridlines are `<line>` and axis labels are `<text>`, so the only
    rects in a plain bar chart are the background and the bars.
    """
    var t = Theme(show_gridlines=False, svg_tooltips=False)
    var svg = render_svg(
        bar(_cats(), _vals(), theme=t, width=400, height=300)
    ).to_string()
    _assert_well_formed_svg(svg, "plain bar chart")

    assert_equal(
        _count_tag(svg, "rect"), 1 + 4, "the background rect plus one per bar"
    )
    var fills = _attr_values(svg, "rect", "fill")
    assert_equal(fills[0], t.background.to_hex(), "the background rect first")
    for i in range(1, len(fills)):
        assert_equal(fills[i], t.mark_color.to_hex(), "bar " + String(i - 1))


def test_grouped_bars_use_each_series_colour_once_per_category() raises:
    """Three categories times two series is six rects, and the palette
    cycles by series rather than by bar: colour 0 appears three times and
    colour 1 three times. Counting the fills is what distinguishes that
    from cycling per bar, which a substring check cannot see.
    """
    var cats: List[String] = ["x", "y", "z"]
    var names: List[String] = ["s1", "s2"]
    var vals = List[List[Float64]]()
    var r0: List[Float64] = [1.0, 2.0, 3.0]
    var r1: List[Float64] = [3.0, 2.0, 1.0]
    vals.append(r0^)
    vals.append(r1^)

    var t = Theme(show_gridlines=False, show_legend=False, svg_tooltips=False)
    var svg = render_svg(
        grouped_bar(cats, names, vals, theme=t, width=420, height=300)
    ).to_string()
    _assert_well_formed_svg(svg, "grouped bar")

    assert_equal(
        _count_tag(svg, "rect"),
        1 + 6,
        "the background rect plus one per (category, series)",
    )
    var palette = default_categorical_palette()
    var fills = _attr_values(svg, "rect", "fill")
    var first = 0
    var second = 0
    for i in range(len(fills)):
        if fills[i] == palette[0].to_hex():
            first += 1
        elif fills[i] == palette[1].to_hex():
            second += 1
    assert_equal(first, 3, "series 1's colour, once per category")
    assert_equal(second, 3, "series 2's colour, once per category")


def test_legend_swatches_are_counted_separately_from_marks() raises:
    """With the legend on, the rects are the bars plus one swatch per
    series -- a total a substring assertion has no way to check, and the
    thing that catches a legend drawn twice or not at all.
    """
    var cats: List[String] = ["x", "y", "z"]
    var names: List[String] = ["s1", "s2"]
    var vals = List[List[Float64]]()
    var r0: List[Float64] = [1.0, 2.0, 3.0]
    var r1: List[Float64] = [3.0, 2.0, 1.0]
    vals.append(r0^)
    vals.append(r1^)

    var t = Theme(show_gridlines=False, svg_tooltips=False)
    var svg = render_svg(
        grouped_bar(cats, names, vals, theme=t, width=420, height=300)
    ).to_string()
    _assert_well_formed_svg(svg, "grouped bar with legend")

    assert_equal(
        _count_tag(svg, "rect"),
        1 + 6 + 2,
        "background, 6 bars, and one swatch per series",
    )


def test_tooltips_wrap_exactly_one_group_per_datum() raises:
    """`svg_tooltips=True` opens one group per datum, each carrying one
    `<title>`, and closes all of them. The count is the assertion: a mark
    that opened a group per *primitive* rather than per datum would still
    contain every expected title.
    """
    var t = Theme(show_gridlines=False, svg_tooltips=True)
    var svg = render_svg(
        bar(_cats(), _vals(), theme=t, width=400, height=300)
    ).to_string()
    _assert_well_formed_svg(svg, "bar with tooltips")

    var titles = _group_titles(svg)
    assert_equal(len(titles), 4, "one title per bar")
    assert_equal(svg.count("<g>"), 4, "one group per bar")
    assert_equal(svg.count("</g>"), 4, "every group closed")
    assert_equal(titles[0], "a: 4", "titles are in document order")
    assert_equal(titles[3], "d: 2", "and cover the last datum")


def test_a_box_plot_puts_all_five_primitives_in_one_group() raises:
    """A box is five primitives but one datum, so it is one group with
    one title -- the case where "count the groups" and "count the shapes"
    genuinely differ, and the reason the tooltip contract is per datum.
    """
    var cats: List[String] = ["A"]
    var vals = List[List[Float64]]()
    # Deliberately outlier-free: an outlier is its own datum and opens
    # its own group, which would make this test about two things.
    var one: List[Float64] = [60.0, 70.0, 75.0, 80.0, 85.0]
    vals.append(one^)

    var t = Theme(show_gridlines=False, show_legend=False, svg_tooltips=True)
    var svg = render_svg(
        box(cats, vals, theme=t, width=320, height=240)
    ).to_string()
    _assert_well_formed_svg(svg, "box plot with tooltips")

    var titles = _group_titles(svg)
    assert_equal(len(titles), 1, "one datum, so one group")
    assert_true(
        "median" in titles[0], "the group's title is the five-number summary"
    )
    assert_true(
        _count_tag(svg, "rect") + _count_tag(svg, "line") > 1,
        "and it wraps more than one primitive",
    )


def test_tooltips_off_leaves_no_groups_and_the_same_marks() raises:
    """Turning tooltips off removes every group and title while leaving
    the mark elements untouched -- the "purely additive markup" claim,
    checked structurally rather than by string length.
    """
    var on = render_svg(
        bar(
            _cats(),
            _vals(),
            theme=Theme(show_gridlines=False, svg_tooltips=True),
            width=400,
            height=300,
        )
    ).to_string()
    var off = render_svg(
        bar(
            _cats(),
            _vals(),
            theme=Theme(show_gridlines=False, svg_tooltips=False),
            width=400,
            height=300,
        )
    ).to_string()
    _assert_well_formed_svg(on, "tooltips on")
    _assert_well_formed_svg(off, "tooltips off")

    assert_equal(len(_group_titles(off)), 0, "no titles with tooltips off")
    assert_equal(off.count("<g>"), 0, "no groups with tooltips off")
    assert_equal(
        _count_tag(on, "rect"),
        _count_tag(off, "rect"),
        "the same bars either way",
    )
    assert_equal(
        _attr_values(on, "rect", "fill")[0],
        _attr_values(off, "rect", "fill")[0],
        "in the same colour either way",
    )


def test_pie_wedges_are_paths_one_per_category_in_palette_order() raises:
    """A pie is one `<path>` per wedge, coloured by the palette in
    category order. Reading `fill` off `<path>` specifically is what
    keeps the legend's `<rect>` swatches out of the comparison.
    """
    var t = Theme(show_legend=True, svg_tooltips=False)
    var svg = render_svg(
        pie(_cats(), _vals(), theme=t, width=420, height=300)
    ).to_string()
    _assert_well_formed_svg(svg, "pie chart")

    var fills = _attr_values(svg, "path", "fill")
    assert_equal(len(fills), 4, "one wedge path per category")
    var palette = default_categorical_palette()
    for i in range(4):
        assert_equal(
            fills[i], palette[i].to_hex(), "wedge " + String(i) + "'s colour"
        )


def test_scatter_points_are_circles_not_rects() raises:
    """Which element a mark emits is part of its contract: points are
    `<circle>`s. A substring check for the fill colour would pass just as
    well if they came out as squares.
    """
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [3.0, 1.0, 2.0]
    var t = Theme(show_gridlines=False, svg_tooltips=False)
    var svg = render_svg(scatter(x, y, theme=t, width=320, height=240))
    var s = svg.to_string()
    _assert_well_formed_svg(s, "scatter")

    assert_equal(_count_tag(s, "circle"), 3, "one circle per point")
    assert_equal(_count_tag(s, "rect"), 1, "and no rects beyond the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
