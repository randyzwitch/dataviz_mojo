"""Plotting named columns of a `dataframe_mojo` `DataFrame` (#364).

The load-bearing test here is `test_a_frame_renders_the_same_bytes_as_the_lists`:
a frame-fed chart must be the same document as the same numbers passed
as lists. Everything else -- which channel a dtype picks, where the axis
titles come from, which columns are refused -- is a claim about the
adapter, and that one is the claim that it adapts and nothing else.
"""

from dataframe import Column, DataFrame, Series

from dataviz import Plot, bar, line, scatter
from dataviz.core.theme import Theme
from dataviz.plot import render_svg
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _frame() raises -> DataFrame:
    """Three rows: a category, two numeric columns, an integer column,
    and one column with a hole in it."""
    return DataFrame(
        [
            Series("region", Column[String](["east", "west", "north"])),
            Series("amount", Column[Float64]([10.0, 22.5, 7.0])),
            Series("net", Column[Float64]([9.0, 20.0, 6.5])),
            Series("units", Column[Int64]([3, 9, 5])),
            Series(
                "holes",
                Column[Float64]([1.0, 2.0, 3.0], [True, False, True]),
            ),
        ]
    )


def test_a_frame_renders_the_same_bytes_as_the_lists() raises:
    """The adapter reads columns and nothing else: the same numbers as
    lists, with the same titles set by hand, must give the same SVG."""
    var df = _frame()
    var from_frame = render_svg(
        scatter(df, x="amount", y="net", width=320, height=240)
    ).to_string()

    var xs: List[Float64] = [10.0, 22.5, 7.0]
    var ys: List[Float64] = [9.0, 20.0, 6.5]
    var from_lists = render_svg(
        scatter(
            xs,
            ys,
            width=320,
            height=240,
            x_title="amount",
            y_title="net",
        )
    ).to_string()
    assert_equal(from_frame, from_lists, "same document, byte for byte")


def test_axis_titles_default_to_the_column_names() raises:
    var svg = render_svg(
        scatter(_frame(), x="amount", y="net", width=320, height=240)
    ).to_string()
    assert_true(">amount<" in svg, "x axis titled by its column")
    assert_true(">net<" in svg, "y axis titled by its column")


def test_encode_frame_titles_the_axes_by_itself() raises:
    """The one-call functions pass the column names down as titles, so
    they would pass this test with `encode_frame` doing nothing. This
    builds the plot the long way, where `encode_frame` is the only thing
    that can title an axis."""
    var plot = (
        Plot()
        .mark_point()
        .encode_frame(_frame(), x="amount", y="net")
        .size(320, 240)
    )
    var svg = render_svg(plot).to_string()
    assert_true(">amount</text>" in svg, "x axis titled by encode_frame")
    assert_true(">net</text>" in svg, "y axis titled by encode_frame")


def test_encode_frame_leaves_a_title_set_before_it_alone() raises:
    var plot = (
        Plot()
        .mark_point()
        .labels(x_title="Spend")
        .encode_frame(_frame(), x="amount", y="net")
        .size(320, 240)
    )
    var svg = render_svg(plot).to_string()
    assert_true(">Spend</text>" in svg, "the earlier title survives")
    assert_true(">amount</text>" not in svg, "and is not joined by the column")


def test_an_explicit_title_beats_the_column_name() raises:
    var svg = render_svg(
        scatter(
            _frame(),
            x="amount",
            y="net",
            y_title="Net revenue",
            width=320,
            height=240,
        )
    ).to_string()
    assert_true(">Net revenue<" in svg, "caller's title wins")
    assert_true(">net<" not in svg, "column name does not also appear")


def test_a_string_x_column_draws_categories() raises:
    """`encode_frame` reads the channel from the dtype: a string x is a
    category axis, so `mark_bar` gets what it needs without the caller
    saying which encoder to use."""
    var svg = render_svg(
        bar(_frame(), x="region", y="amount", width=320, height=240)
    ).to_string()
    assert_true(">east<" in svg and ">north<" in svg, "categories drawn")


def test_an_integer_column_is_accepted_as_a_continuous_channel() raises:
    """Every axis here is Float64, so any numeric dtype is cast rather
    than refused."""
    var svg = render_svg(
        scatter(_frame(), x="units", y="net", width=320, height=240)
    ).to_string()
    assert_true(">units<" in svg, "an Int64 column plots")


def test_a_string_color_column_gives_each_category_its_own_color() raises:
    var plot = (
        Plot()
        .mark_point()
        .encode_frame(_frame(), x="amount", y="net", color="region")
        .size(360, 240)
    )
    var svg = render_svg(plot).to_string()
    assert_true(">east<" in svg, "the legend names the categories")
    var colors = List[String]()
    var at = 0
    while True:
        var i = svg.find('fill="#', at)
        if i < 0:
            break
        var color = String(svg[byte = i + 6 : i + 13])
        var seen = False
        for c in colors:
            if c == color:
                seen = True
        if not seen:
            colors.append(color)
        at = i + 7
    assert_true(len(colors) >= 3, "three categories, three fills")


def test_a_numeric_color_column_uses_the_continuous_scale() raises:
    var plot = (
        Plot()
        .mark_point()
        .encode_frame(_frame(), x="amount", y="net", color="units")
        .size(360, 240)
    )
    var svg = render_svg(plot).to_string()
    assert_true(
        ">3.0<" in svg and ">9.0<" in svg,
        "the colorbar runs from the column's low to its high",
    )


def test_a_missing_column_names_what_the_frame_has() raises:
    with assert_raises(contains='no column named "nope"'):
        _ = scatter(_frame(), x="nope", y="net")
    with assert_raises(contains="region, amount, net, units, holes"):
        _ = scatter(_frame(), x="nope", y="net")


def test_a_string_column_is_refused_for_a_continuous_channel() raises:
    with assert_raises(contains="not a numeric column"):
        _ = scatter(_frame(), x="amount", y="region")


def test_a_numeric_column_is_refused_for_a_categorical_channel() raises:
    with assert_raises(contains="not a string column"):
        _ = (
            Plot()
            .mark_point()
            .encode_frame(_frame(), x="amount", y="net", labels="units")
        )


def test_a_column_with_holes_raises_and_points_at_the_open_question() raises:
    """What a mark draws for a gap is #367. Until that is decided the
    adapter refuses rather than dropping the row or drawing a zero."""
    with assert_raises(contains='column "holes" has 1 missing value(s)'):
        _ = scatter(_frame(), x="amount", y="holes")
    with assert_raises(contains="the first at row 1"):
        _ = scatter(_frame(), x="amount", y="holes")
    with assert_raises(contains="dataviz_mojo#367"):
        _ = scatter(_frame(), x="amount", y="holes")


def test_a_categorical_x_refuses_the_point_only_channels() raises:
    with assert_raises(contains="takes no size= or labels= channel"):
        _ = (
            Plot()
            .mark_bar()
            .encode_frame(_frame(), x="region", y="amount", size="units")
        )


def test_a_frame_line_and_bar_carry_their_column_names() raises:
    var l = render_svg(
        line(_frame(), x="amount", y="net", width=320, height=240)
    ).to_string()
    assert_true(">amount<" in l and ">net<" in l, "line titles")
    var b = render_svg(
        bar(_frame(), x="region", y="amount", width=320, height=240)
    ).to_string()
    assert_true(">region<" in b and ">amount<" in b, "bar titles")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
