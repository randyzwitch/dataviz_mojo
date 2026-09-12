"""Structural SVG assertions.

The SVG tests elsewhere assert on `to_string()` substrings. That catches
gross breakage but not structure: a mark emitting its rects outside the
annotated tooltip group, an unclosed `<g>`, or a legend drawing the right
colors the wrong number of times all pass a substring check.

These count elements, read attributes per element type, and pull the
`<title>` out of annotated groups (`_test_helpers.mojo`), so an assertion
can say "N bars produce exactly N `<rect>`s, in these N colors" rather
than "this color appears somewhere".

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
    _drawn,
)
from dataviz import bar, box, grouped_bar, pie, rugplot, scatter
from dataviz.core.color_scale import default_categorical_palette
from dataviz.plot import Plot, render_svg
from dataviz.core.theme import Theme
from std.testing import TestSuite, assert_equal, assert_true


def _cats() -> List[String]:
    return ["a", "b", "c", "d"]


def _vals() -> List[Float64]:
    return [4.0, 1.0, 3.0, 2.0]


def test_bars_produce_one_rect_each_in_the_mark_color() raises:
    """Four bars are four `<rect>`s in `Theme.mark_color`, after the
    document's background rect -- not "the color appears somewhere",
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


def test_attr_values_reads_an_elements_first_attribute() raises:
    """`_attr_values` could not read the first attribute of an element
    , and returned an empty list rather than saying so -- which in
        a test reads as an assertion that passes over no values at all.

        Every caller until now asked for `fill`, which canvas never emits
        first, so the gap stayed invisible. canvas writes a bar as
        `<rect x=... y=... width=... height=... fill=.../>`, so `x` is the
        case that used to come back empty.

        This asserts against `fill` from the same document rather than
        against fixed coordinates: the point is that the two attributes are
        read equally well, not where this particular chart puts its bars.
    """
    var t = Theme(show_gridlines=False, svg_tooltips=False)
    var svg = render_svg(
        bar(_cats(), _vals(), theme=t, width=400, height=300)
    ).to_string()

    var xs = _attr_values(svg, "rect", "x")
    var fills = _attr_values(svg, "rect", "fill")
    assert_equal(
        len(xs),
        len(fills),
        "every rect carries both x and fill, so the counts must agree",
    )
    assert_equal(len(xs), 1 + 4, "the background rect plus one per bar")

    # The bars are left to right in document order, so their x values
    # strictly increase. That the values parse and are ordered is what
    # says they were really read, rather than something being returned.
    for i in range(2, len(xs)):
        assert_true(
            atol(xs[i]) > atol(xs[i - 1]),
            (
                "bar x values should increase left to right -- got "
                + xs[i - 1]
                + " then "
                + xs[i]
            ),
        )


def _gridline_strokes_of(svg: String) -> List[String]:
    """The `stroke` of every `<line>` in an already-rendered document."""
    return _attr_values(svg, "line", "stroke")


def _gridline_strokes(theme: Theme) raises -> List[String]:
    """The `stroke` of every `<line>` in a plain scatter under `theme` --
    gridlines, axis lines and tick marks, which is everything drawn as a
    line."""
    var xs: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var ys: List[Float64] = [2.0, 5.0, 3.0, 8.0, 6.0]
    var svg = render_svg(
        scatter(xs, ys, theme=theme, width=520, height=340)
    ).to_string()
    return _attr_values(svg, "line", "stroke")


def _count_of(values: List[String], wanted: String) -> Int:
    var n = 0
    for v in values:
        if v == wanted:
            n += 1
    return n


def test_minor_gridlines_and_ticks_are_off_by_default() raises:
    """Adds a minor tick level, and both halves are opt-in: a
    default chart must be exactly what it was before.

    Asserting on the minor gridline color specifically, rather than a
    total line count, so this keeps meaning the right thing if some
    unrelated change adds furniture.
    """
    var t = Theme()
    var strokes = _gridline_strokes(t)
    assert_equal(
        _count_of(strokes, t.minor_gridline_color.to_hex()),
        0,
        "no minor gridlines in a default chart",
    )
    assert_true(
        _count_of(strokes, t.gridline_color.to_hex()) > 0,
        "major gridlines are still drawn by default",
    )


def test_minor_gridlines_are_drawn_when_asked_and_are_lighter() raises:
    """Turning them on adds lines in `minor_gridline_color`, and there
    are more of them than major ones -- four minors per major gap on a
    linear axis.

    The color has to be lighter than `gridline_color` or the chart gets
    busier rather than more readable: the eye can no longer tell which
    lines carry the labeled values.
    """
    var t = Theme(show_minor_gridlines=True)
    var strokes = _gridline_strokes(t)
    var minors = _count_of(strokes, t.minor_gridline_color.to_hex())
    var majors = _count_of(strokes, t.gridline_color.to_hex())

    assert_true(minors > 0, "minor gridlines are drawn when asked")
    assert_true(
        minors > majors,
        (
            "there are more minor gridlines than major ones -- got "
            + String(minors)
            + " minor, "
            + String(majors)
            + " major"
        ),
    )

    # Lighter means a higher channel value on a light background. All
    # three channels, so this cannot pass on a hue difference alone.
    assert_true(
        Int(t.minor_gridline_color.r) > Int(t.gridline_color.r)
        and Int(t.minor_gridline_color.g) > Int(t.gridline_color.g)
        and Int(t.minor_gridline_color.b) > Int(t.gridline_color.b),
        "the minor gridline color is lighter than the major one",
    )


def test_a_suppressed_y_axis_takes_its_minor_level_with_it() raises:
    """A standalone rugplot drops its y-axis, and the minor level
    has to go with it: a horizontal gridline or a y tick has
       nothing to mean against a scale that is not drawn.

       Both code paths must remain equivalent, so
       is exactly the case where an ungated loop survives unnoticed -- so
       this pins it rather than trusting the merge.
    """
    var values: List[Float64] = [12.0, 14.0, 15.0, 17.0, 24.0, 26.0, 28.0]
    var t = Theme(show_minor_ticks=True, show_minor_gridlines=True)
    var svg = render_svg(
        rugplot(values, theme=t, width=420, height=260)
    ).to_string()

    # Horizontal *gridlines* specifically. The x-axis line is horizontal
    # too and is drawn on purpose, so counting every horizontal line
    # would assert something false -- it did on the first run, and the
    # one line it found was the axis.
    var y1s = _attr_values(svg, "line", "y1")
    var y2s = _attr_values(svg, "line", "y2")
    var strokes = _gridline_strokes_of(svg)
    var horizontal_gridlines = 0
    for i in range(len(y1s)):
        var is_grid = (
            strokes[i] == t.gridline_color.to_hex()
            or strokes[i] == t.minor_gridline_color.to_hex()
        )
        if y1s[i] == y2s[i] and is_grid:
            horizontal_gridlines += 1
    assert_equal(
        horizontal_gridlines,
        0,
        (
            "a rugplot has no y-axis, so no horizontal gridline can mean"
            " anything -- got "
            + String(horizontal_gridlines)
        ),
    )

    # The x-axis keeps its own minor level: that axis is real here.
    assert_true(
        _count_of(strokes, t.minor_gridline_color.to_hex()) > 0,
        "the x-axis minor gridlines are still drawn",
    )


def test_grouped_bars_use_each_series_color_once_per_category() raises:
    """Three categories times two series is six rects, and the palette
    cycles by series rather than by bar: color 0 appears three times and
    color 1 three times. Counting the fills is what distinguishes that
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
    assert_equal(first, 3, "series 1's color, once per category")
    assert_equal(second, 3, "series 2's color, once per category")


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
        "in the same color either way",
    )


def test_pie_wedges_are_paths_one_per_category_in_palette_order() raises:
    """A pie is one `<path>` per wedge, colored by the palette in
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
            fills[i], palette[i].to_hex(), "wedge " + String(i) + "'s color"
        )


def test_scatter_points_are_circles_not_rects() raises:
    """Which element a mark emits is part of its contract: points are
    `<circle>`s. A substring check for the fill color would pass just as
    well if they came out as squares.
    """
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [3.0, 1.0, 2.0]
    var t = Theme(show_gridlines=False, svg_tooltips=False)
    var svg = render_svg(scatter(x, y, theme=t, width=320, height=240))
    var s = svg.to_string()
    _assert_well_formed_svg(s, "scatter")

    assert_equal(_count_tag(_drawn(s), "circle"), 3, "one circle per point")
    assert_equal(
        _count_tag(_drawn(s), "rect"), 1, "and no rects beyond the background"
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
