"""Faceting a frame by a column (#364).

`facet_by` splits a frame into one part per level, and every mark
already takes a frame, so a faceted figure is a loop rather than a
facet-shaped variant of each of the 78 one-call functions.

The claim worth testing is that the split is *faithful*: every row
lands in exactly one part, in the order the table had them, and a part
drawn on its own is the same chart as the same rows passed as lists.
"""

from dataframe import Column, DataFrame, Series

from dataviz import Plot, facet_by, pooled_extent, scatter
from dataviz.core.missing import Missing
from dataviz.core.theme import Theme
from dataviz.plot import render_svg
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _sales() raises -> DataFrame:
    """Nine rows over three regions, interleaved."""
    var region = List[String]()
    var spend = List[Float64]()
    var revenue = List[Float64]()
    var names: List[String] = ["north", "south", "east"]
    for i in range(9):
        region.append(names[i % 3])
        spend.append(Float64(i) * 2.0)
        revenue.append(Float64(i) * 3.0 + 1.0)
    return DataFrame(
        [
            Series("region", Column[String](region.copy())),
            Series("spend", Column[Float64](spend.copy())),
            Series("revenue", Column[Float64](revenue.copy())),
        ]
    )


def test_every_row_lands_in_exactly_one_part() raises:
    var parts = facet_by(_sales(), "region")
    assert_equal(len(parts), 3, "three levels")
    var total = 0
    for p in parts:
        total += p.frame.height()
    assert_equal(total, 9, "no row lost, none duplicated")
    assert_equal(parts[0].frame.height(), 3, "three rows per region here")


def test_parts_come_in_first_appearance_order() raises:
    var parts = facet_by(_sales(), "region")
    assert_equal(parts[0].name, "north", "the first row's level first")
    assert_equal(parts[1].name, "south")
    assert_equal(parts[2].name, "east")


def test_a_part_draws_the_same_chart_as_its_rows_as_lists() raises:
    """The split is faithful: a panel is the rows that carry its level,
    in the table's order, and nothing else."""
    var parts = facet_by(_sales(), "region")
    var by_part = render_svg(
        scatter(parts[0].frame, x="spend", y="revenue", width=280, height=220)
    ).to_string()

    # north is rows 0, 3 and 6.
    var xs: List[Float64] = [0.0, 6.0, 12.0]
    var ys: List[Float64] = [1.0, 10.0, 19.0]
    var by_hand = render_svg(
        scatter(
            xs,
            ys,
            width=280,
            height=220,
            x_title="spend",
            y_title="revenue",
        )
    ).to_string()
    assert_equal(by_part, by_hand, "same document, byte for byte")


def test_a_numeric_column_facets_by_its_values() raises:
    var df = DataFrame(
        [
            Series("year", Column[Int64]([2024, 2025, 2024])),
            Series("value", Column[Float64]([1.0, 2.0, 3.0])),
        ]
    )
    var parts = facet_by(df, "year")
    assert_equal(len(parts), 2, "two years")
    assert_equal(parts[0].frame.height(), 2, "2024 has two rows")


def test_rows_with_no_level_are_gathered_under_one_name() raises:
    """A missing level is a label like any other (#367): those rows keep
    their values and get a panel of their own."""
    var df = DataFrame(
        [
            Series(
                "region",
                Column[String](
                    ["north", "south", "north"], [True, False, True]
                ),
            ),
            Series("value", Column[Float64]([1.0, 2.0, 3.0])),
        ]
    )
    var parts = facet_by(df, "region")
    assert_equal(len(parts), 2, "north, and the rows with no region")
    assert_equal(parts[1].name, "(missing)")
    assert_equal(parts[1].frame.height(), 1, "that row is kept, not dropped")


def test_strict_mode_refuses_a_missing_level() raises:
    var df = DataFrame(
        [
            Series("region", Column[String](["a", "b"], [True, False])),
            Series("value", Column[Float64]([1.0, 2.0])),
        ]
    )
    with assert_raises(contains="missing value(s)"):
        _ = facet_by(df, "region", Missing.RAISE)


def test_a_missing_column_is_named() raises:
    with assert_raises(contains='no column named "nope"'):
        _ = facet_by(_sales(), "nope")


def test_pooled_extent_spans_the_whole_frame() raises:
    """A panel scaled from its own rows says nothing about the panel
    beside it, so the pooled extent is what makes the comparison
    fair."""
    var df = _sales()
    var extent = pooled_extent(df, "revenue")
    assert_equal(extent[0], 1.0, "the lowest revenue anywhere")
    assert_equal(extent[1], 25.0, "and the highest")

    var parts = facet_by(df, "region")
    var own = pooled_extent(parts[0].frame, "revenue")
    assert_true(
        own[1] < extent[1], "one part's own high is below the pooled high"
    )


def test_pooled_extent_ignores_missing_values() raises:
    var df = DataFrame(
        [
            Series(
                "value",
                Column[Float64]([2.0, 9.0, 4.0], [True, False, True]),
            ),
        ]
    )
    var extent = pooled_extent(df, "value")
    assert_equal(extent[1], 4.0, "the missing 9 takes no part")


def test_panels_given_the_pooled_extent_share_an_axis() raises:
    var df = _sales()
    var extent = pooled_extent(df, "revenue")
    var panels = List[Plot]()
    for part in facet_by(df, "region"):
        panels.append(
            scatter(
                part.frame,
                x="spend",
                y="revenue",
                title=part.name,
                width=240,
                height=200,
            ).scale_y_domain(extent[0], extent[1])
        )
    var first = render_svg(panels[0].copy()).to_string()
    var last = render_svg(panels[2].copy()).to_string()
    # The same y tick labels appear in both, which is what a shared axis
    # means to a reader comparing the panels.
    assert_true(">25<" in first or ">25.0<" in first, "the pooled high")
    assert_true(">25<" in last or ">25.0<" in last, "in both panels")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
