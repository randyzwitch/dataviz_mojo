"""Long-form frames for the distribution marks (#743, tier 2).

A dataframe holds observations long -- one row each, with a category
beside it -- while `box()` and its family take one list of values per
category. `_frame_groups` buckets the rows, and the test that matters
is `test_grouping_matches_the_lists_built_by_hand`: the grouped call
must render the same document as the nested lists a caller would have
written themselves.
"""

from dataframe import Column, DataFrame, Series

from dataviz import (
    beeswarm,
    box,
    boxenplot,
    grouped_bar,
    marimekko,
    ridgeline,
    stacked_area,
    stacked_bar,
    streamgraph,
    violin,
)
from dataviz.core.frame_input import _frame_groups, _frame_series
from dataviz.plot import render_svg
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _long_frame() raises -> DataFrame:
    """Nine observations over three species, deliberately interleaved so
    a grouping that followed row order rather than category would show
    up."""
    return DataFrame(
        [
            Series(
                "species",
                Column[String](
                    [
                        "gentoo",
                        "adelie",
                        "chinstrap",
                        "adelie",
                        "gentoo",
                        "adelie",
                        "chinstrap",
                        "gentoo",
                        "chinstrap",
                    ]
                ),
            ),
            Series(
                "mass_kg",
                Column[Float64]([5.0, 3.7, 3.9, 3.8, 5.4, 4.1, 4.0, 5.2, 3.6]),
            ),
        ]
    )


def test_grouping_matches_the_lists_built_by_hand() raises:
    """The whole claim of the tier: grouping a long frame gives the same
    chart as the nested lists, including the category order."""
    var by_frame = render_svg(
        box(
            _long_frame(),
            category="species",
            value="mass_kg",
            width=420,
            height=300,
        )
    ).to_string()

    # First appearance decides the order: gentoo, adelie, chinstrap.
    var cats: List[String] = ["gentoo", "adelie", "chinstrap"]
    var values = List[List[Float64]]()
    var gentoo: List[Float64] = [5.0, 5.4, 5.2]
    var adelie: List[Float64] = [3.7, 3.8, 4.1]
    var chinstrap: List[Float64] = [3.9, 4.0, 3.6]
    values.append(gentoo^)
    values.append(adelie^)
    values.append(chinstrap^)
    var by_hand = render_svg(
        box(
            cats,
            values,
            width=420,
            height=300,
            x_title="species",
            y_title="mass_kg",
        )
    ).to_string()
    assert_equal(by_frame, by_hand, "same document, byte for byte")


def test_groups_keep_first_appearance_order() raises:
    var groups = _frame_groups(_long_frame(), "species", "mass_kg", "t")
    ref order = groups[0]
    assert_equal(len(order), 3, "three species")
    assert_equal(order[0], "gentoo", "first row's category comes first")
    assert_equal(order[1], "adelie")
    assert_equal(order[2], "chinstrap")


def test_each_group_keeps_its_rows_in_row_order() raises:
    var groups = _frame_groups(_long_frame(), "species", "mass_kg", "t")
    ref values = groups[1]
    assert_equal(len(values[0]), 3, "three gentoo rows")
    assert_equal(values[0][0], 5.0, "in the order the frame had them")
    assert_equal(values[0][1], 5.4)
    assert_equal(values[0][2], 5.2)
    assert_equal(values[1][0], 3.7, "adelie's first row")


def test_every_distribution_mark_takes_a_long_frame() raises:
    var df = _long_frame()
    var svgs = List[String]()
    svgs.append(
        render_svg(
            box(df, category="species", value="mass_kg", width=420, height=300)
        ).to_string()
    )
    svgs.append(
        render_svg(
            violin(
                df, category="species", value="mass_kg", width=420, height=300
            )
        ).to_string()
    )
    svgs.append(
        render_svg(
            beeswarm(
                df, category="species", value="mass_kg", width=420, height=300
            )
        ).to_string()
    )
    svgs.append(
        render_svg(
            boxenplot(
                df, category="species", value="mass_kg", width=420, height=300
            )
        ).to_string()
    )
    svgs.append(
        render_svg(
            ridgeline(
                df, category="species", value="mass_kg", width=420, height=300
            )
        ).to_string()
    )
    for svg in svgs:
        assert_true(">gentoo<" in svg, "every mark draws the categories")
        assert_true(">species<" in svg, "and titles the axis by the column")


def test_a_long_frame_mark_takes_its_own_options() raises:
    """The overload forwards what the list version takes, so a
    horizontal box or a wider violin still works from a frame."""
    var df = _long_frame()
    var flat = render_svg(
        box(
            df,
            category="species",
            value="mass_kg",
            horizontal=True,
            width=420,
            height=300,
        )
    ).to_string()
    var upright = render_svg(
        box(df, category="species", value="mass_kg", width=420, height=300)
    ).to_string()
    assert_true(flat != upright, "horizontal=True reaches the mark")

    var wide = render_svg(
        violin(
            df,
            category="species",
            value="mass_kg",
            width_fraction=0.9,
            width=420,
            height=300,
        )
    ).to_string()
    var narrow = render_svg(
        violin(df, category="species", value="mass_kg", width=420, height=300)
    ).to_string()
    assert_true(wide != narrow, "width_fraction reaches the mark")


def test_a_hole_in_either_column_raises() raises:
    var df = DataFrame(
        [
            Series("species", Column[String](["a", "b", "c"])),
            Series(
                "mass_kg",
                Column[Float64]([1.0, 2.0, 3.0], [True, False, True]),
            ),
        ]
    )
    with assert_raises(contains='column "mass_kg" has 1 missing value(s)'):
        _ = box(df, category="species", value="mass_kg")


def test_a_numeric_category_column_is_refused() raises:
    var df = DataFrame(
        [
            Series("group_id", Column[Int64]([1, 1, 2])),
            Series("mass_kg", Column[Float64]([1.0, 2.0, 3.0])),
        ]
    )
    with assert_raises(contains="not a string column"):
        _ = box(df, category="group_id", value="mass_kg")


def _tidy_frame() raises -> DataFrame:
    """Two quarters by two products, long: four rows, deliberately not
    grouped by either key."""
    return DataFrame(
        [
            Series(
                "quarter",
                Column[String](["Q1", "Q2", "Q1", "Q2"]),
            ),
            Series(
                "product",
                Column[String](["widgets", "widgets", "gadgets", "gadgets"]),
            ),
            Series("revenue", Column[Float64]([10.0, 12.0, 7.0, 9.0])),
        ]
    )


def test_the_pivot_matches_the_series_rows_built_by_hand() raises:
    var by_frame = render_svg(
        grouped_bar(
            _tidy_frame(),
            category="quarter",
            series="product",
            value="revenue",
            width=420,
            height=300,
        )
    ).to_string()

    var cats: List[String] = ["Q1", "Q2"]
    var names: List[String] = ["widgets", "gadgets"]
    var values = List[List[Float64]]()
    var widgets: List[Float64] = [10.0, 12.0]
    var gadgets: List[Float64] = [7.0, 9.0]
    values.append(widgets^)
    values.append(gadgets^)
    var by_hand = render_svg(
        grouped_bar(
            cats,
            names,
            values,
            width=420,
            height=300,
            x_title="quarter",
            y_title="revenue",
        )
    ).to_string()
    assert_equal(by_frame, by_hand, "same document, byte for byte")


def test_the_pivot_keeps_both_orders_by_first_appearance() raises:
    var pivot = _frame_series(
        _tidy_frame(), "quarter", "product", "revenue", "t"
    )
    ref cats = pivot[0]
    ref names = pivot[1]
    ref values = pivot[2]
    assert_equal(cats[0], "Q1")
    assert_equal(names[0], "widgets", "the first row's series comes first")
    assert_equal(names[1], "gadgets")
    assert_equal(values[0][1], 12.0, "widgets in Q2")
    assert_equal(values[1][0], 7.0, "gadgets in Q1")


def test_a_missing_pair_raises_rather_than_reading_as_zero() raises:
    """A cell with no row is not a zero, and guessing would be a claim
    about the data the frame never made."""
    var df = DataFrame(
        [
            Series("quarter", Column[String](["Q1", "Q2", "Q1"])),
            Series(
                "product",
                Column[String](["widgets", "widgets", "gadgets"]),
            ),
            Series("revenue", Column[Float64]([10.0, 12.0, 7.0])),
        ]
    )
    with assert_raises(contains='no row for series "gadgets" in category "Q2"'):
        _ = grouped_bar(
            df, category="quarter", series="product", value="revenue"
        )


def test_a_repeated_pair_raises_rather_than_picking_one() raises:
    var df = DataFrame(
        [
            Series("quarter", Column[String](["Q1", "Q1"])),
            Series("product", Column[String](["widgets", "widgets"])),
            Series("revenue", Column[Float64]([10.0, 4.0])),
        ]
    )
    with assert_raises(contains="more than one row for series"):
        _ = grouped_bar(
            df, category="quarter", series="product", value="revenue"
        )


def test_every_multi_series_mark_takes_a_long_frame() raises:
    var df = _tidy_frame()
    var svgs = List[String]()
    svgs.append(
        render_svg(
            stacked_bar(
                df,
                category="quarter",
                series="product",
                value="revenue",
                width=420,
                height=300,
            )
        ).to_string()
    )
    svgs.append(
        render_svg(
            streamgraph(
                df,
                category="quarter",
                series="product",
                value="revenue",
                width=420,
                height=300,
            )
        ).to_string()
    )
    svgs.append(
        render_svg(
            stacked_area(
                df,
                category="quarter",
                series="product",
                value="revenue",
                width=420,
                height=300,
            )
        ).to_string()
    )
    svgs.append(
        render_svg(
            marimekko(
                df,
                category="quarter",
                series="product",
                value="revenue",
                width=420,
                height=300,
            )
        ).to_string()
    )
    for svg in svgs:
        assert_true(">widgets<" in svg, "every mark names its series")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
