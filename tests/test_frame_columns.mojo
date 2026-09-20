"""Flat-column frame overloads (#743, tier 1).

Forty-two one-call functions gained an overload that names columns
instead of taking lists. They were generated from the existing
signatures, so the risk is not in any one of them but in the shapes:
a column read into the wrong argument, an optional channel that reads
when it should not, titles defaulted from the wrong column.

So each test here pins one *shape* -- two columns, three, four, a
boolean flag column, an optional channel -- by rendering the frame call
and the list call and demanding the same bytes.
"""

from dataframe import Column, DataFrame, Series

from dataviz import (
    calendar_heatmap,
    candlestick,
    funnel,
    heatmap,
    histogram,
    pie,
    polar,
    quiver,
    sankey,
    scatter3d,
    treemap,
    waterfall,
)
from dataviz.plot import render_svg
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _cats() -> List[String]:
    return ["north", "south", "east"]


def _vals() -> List[Float64]:
    return [12.0, 7.5, 19.0]


def _cat_frame() raises -> DataFrame:
    return DataFrame(
        [
            Series("region", Column[String](_cats())),
            Series("amount", Column[Float64](_vals())),
        ]
    )


def test_two_columns_one_string_one_number() raises:
    var by_frame = render_svg(
        pie(
            _cat_frame(),
            categories="region",
            values="amount",
            width=360,
            height=260,
        )
    ).to_string()
    # Mark.ARC has no axes: pie raises on x_title/y_title, so its
    # frame overload must not default them from the column names.
    var by_list = render_svg(
        pie(_cats(), _vals(), width=360, height=260)
    ).to_string()
    assert_equal(by_frame, by_list, "pie: same document")


def test_two_columns_both_numbers() raises:
    var xs: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var ys: List[Float64] = [1.0, 3.0, 2.0, 5.0]
    var df = DataFrame(
        [
            Series("angle", Column[Float64](xs.copy())),
            Series("radius", Column[Float64](ys.copy())),
        ]
    )
    var by_frame = render_svg(
        polar(df, angle="angle", radius="radius", width=360, height=300)
    ).to_string()
    var by_list = render_svg(
        polar(
            xs,
            ys,
            width=360,
            height=300,
            x_title="angle",
            y_title="radius",
        )
    ).to_string()
    assert_equal(by_frame, by_list, "polar: same document")


def test_three_columns_two_strings_and_a_number() raises:
    var xs: List[String] = ["Mon", "Mon", "Tue"]
    var ys: List[String] = ["09:00", "10:00", "09:00"]
    var vs: List[Float64] = [4.0, 9.0, 2.0]
    var df = DataFrame(
        [
            Series("day", Column[String](xs.copy())),
            Series("hour", Column[String](ys.copy())),
            Series("count", Column[Float64](vs.copy())),
        ]
    )
    var by_frame = render_svg(
        heatmap(df, x="day", y="hour", value="count", width=400, height=300)
    ).to_string()
    var by_list = render_svg(
        heatmap(xs, ys, vs, width=400, height=300)
    ).to_string()
    assert_equal(by_frame, by_list, "heatmap: same document")


def test_four_numeric_columns() raises:
    var xs: List[Float64] = [0.0, 1.0, 0.0, 1.0]
    var ys: List[Float64] = [0.0, 0.0, 1.0, 1.0]
    var us: List[Float64] = [1.0, 0.5, -0.5, -1.0]
    var vs: List[Float64] = [0.2, 1.0, 0.8, -0.3]
    var df = DataFrame(
        [
            Series("x", Column[Float64](xs.copy())),
            Series("y", Column[Float64](ys.copy())),
            Series("u", Column[Float64](us.copy())),
            Series("v", Column[Float64](vs.copy())),
        ]
    )
    var by_frame = render_svg(
        quiver(df, x="x", y="y", u="u", v="v", width=360, height=300)
    ).to_string()
    var by_list = render_svg(
        quiver(xs, ys, us, vs, width=360, height=300)
    ).to_string()
    assert_equal(by_frame, by_list, "quiver: same document")


def test_five_columns_with_four_numbers() raises:
    var days: List[String] = ["Mon", "Tue"]
    var o: List[Float64] = [10.0, 11.0]
    var h: List[Float64] = [12.0, 13.0]
    var l: List[Float64] = [9.0, 10.5]
    var c: List[Float64] = [11.0, 12.5]
    var df = DataFrame(
        [
            Series("day", Column[String](days.copy())),
            Series("open", Column[Float64](o.copy())),
            Series("high", Column[Float64](h.copy())),
            Series("low", Column[Float64](l.copy())),
            Series("close", Column[Float64](c.copy())),
        ]
    )
    var by_frame = render_svg(
        candlestick(
            df,
            categories="day",
            open="open",
            high="high",
            low="low",
            close="close",
            width=400,
            height=300,
        )
    ).to_string()
    var by_list = render_svg(
        candlestick(days, o, h, l, c, width=400, height=300)
    ).to_string()
    assert_equal(by_frame, by_list, "candlestick: same document")


def test_a_boolean_flag_column() raises:
    """`waterfall`'s `is_total` is the one boolean channel, and a
    boolean column is not a number: reading it as one would draw a
    different chart."""
    var stages: List[String] = ["Start", "Sales", "End"]
    var deltas: List[Float64] = [50.0, 30.0, 0.0]
    var totals: List[Bool] = [True, False, True]
    var df = DataFrame(
        [
            Series("stage", Column[String](stages.copy())),
            Series("delta", Column[Float64](deltas.copy())),
            Series("is_total", Column[Bool](totals.copy())),
        ]
    )
    var by_frame = render_svg(
        waterfall(
            df,
            categories="stage",
            deltas="delta",
            is_total="is_total",
            width=400,
            height=300,
        )
    ).to_string()
    var by_list = render_svg(
        waterfall(stages, deltas, is_total=totals, width=400, height=300)
    ).to_string()
    assert_equal(by_frame, by_list, "waterfall: same document")


def test_a_numeric_column_is_refused_for_the_flag_channel() raises:
    var df = DataFrame(
        [
            Series("stage", Column[String](["a", "b"])),
            Series("delta", Column[Float64]([1.0, 2.0])),
            Series("flag", Column[Int64]([1, 0])),
        ]
    )
    with assert_raises(contains="not a boolean column"):
        _ = waterfall(df, categories="stage", deltas="delta", is_total="flag")


def test_an_optional_channel_left_empty_is_not_read() raises:
    """`histogram`'s `weights` defaults to no column at all, which has
    to mean unweighted rather than a column named empty."""
    var data: List[Float64] = [1.0, 2.0, 2.5, 3.0, 7.0, 8.0]
    var df = DataFrame([Series("value", Column[Float64](data.copy()))])
    var by_frame = render_svg(
        histogram(df, data="value", bins=4, width=400, height=300)
    ).to_string()
    var by_list = render_svg(
        histogram(
            data,
            4,
            width=400,
            height=300,
            x_title="value",
        )
    ).to_string()
    assert_equal(by_frame, by_list, "histogram: same document, unweighted")


def test_an_optional_channel_named_is_read() raises:
    var data: List[Float64] = [1.0, 2.0, 2.5, 3.0, 7.0, 8.0]
    var weights: List[Float64] = [1.0, 1.0, 5.0, 1.0, 1.0, 1.0]
    var df = DataFrame(
        [
            Series("value", Column[Float64](data.copy())),
            Series("weight", Column[Float64](weights.copy())),
        ]
    )
    var weighted = render_svg(
        histogram(
            df, data="value", bins=4, weights="weight", width=400, height=300
        )
    ).to_string()
    var plain = render_svg(
        histogram(df, data="value", bins=4, width=400, height=300)
    ).to_string()
    assert_true(weighted != plain, "the weights column reaches the mark")


def test_a_hierarchy_reads_three_columns_in_order() raises:
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 3.0, 5.0]
    var df = DataFrame(
        [
            Series("id", Column[String](ids.copy())),
            Series("parent", Column[String](parents.copy())),
            Series("size", Column[Float64](values.copy())),
        ]
    )
    var by_frame = render_svg(
        treemap(
            df,
            ids="id",
            parent_ids="parent",
            values="size",
            width=400,
            height=300,
        )
    ).to_string()
    var by_list = render_svg(
        treemap(ids, parents, values, width=400, height=300)
    ).to_string()
    assert_equal(by_frame, by_list, "treemap: same document")


def test_an_edge_list_reads_three_columns_in_order() raises:
    var src: List[String] = ["a", "a", "b"]
    var dst: List[String] = ["b", "c", "c"]
    var w: List[Float64] = [4.0, 2.0, 6.0]
    var df = DataFrame(
        [
            Series("src", Column[String](src.copy())),
            Series("dst", Column[String](dst.copy())),
            Series("flow", Column[Float64](w.copy())),
        ]
    )
    var by_frame = render_svg(
        sankey(
            df,
            from_categories="src",
            to_categories="dst",
            values="flow",
            width=420,
            height=300,
        )
    ).to_string()
    var by_list = render_svg(
        sankey(src, dst, w, width=420, height=300)
    ).to_string()
    assert_equal(by_frame, by_list, "sankey: same document")


def test_three_numeric_columns_in_space() raises:
    var xs: List[Float64] = [0.0, 1.0, 2.0]
    var ys: List[Float64] = [1.0, 0.0, 2.0]
    var zs: List[Float64] = [2.0, 1.0, 0.0]
    var df = DataFrame(
        [
            Series("x", Column[Float64](xs.copy())),
            Series("y", Column[Float64](ys.copy())),
            Series("z", Column[Float64](zs.copy())),
        ]
    )
    var by_frame = render_svg(
        scatter3d(df, x="x", y="y", z="z", width=360, height=320)
    ).to_string()
    var by_list = render_svg(
        scatter3d(xs, ys, zs, width=360, height=320)
    ).to_string()
    assert_equal(by_frame, by_list, "scatter3d: same document")


def test_a_date_column_reaches_the_calendar() raises:
    var dates: List[String] = ["2026-01-01", "2026-01-02", "2026-02-11"]
    var counts: List[Float64] = [3.0, 8.0, 5.0]
    var df = DataFrame(
        [
            Series("day", Column[String](dates.copy())),
            Series("commits", Column[Float64](counts.copy())),
        ]
    )
    var by_frame = render_svg(
        calendar_heatmap(
            df, dates="day", values="commits", width=640, height=220
        )
    ).to_string()
    var by_list = render_svg(
        calendar_heatmap(
            dates,
            counts,
            width=640,
            height=220,
            x_title="day",
            y_title="commits",
        )
    ).to_string()
    assert_equal(by_frame, by_list, "calendar_heatmap: same document")


def test_a_missing_column_still_names_the_frame_s_columns() raises:
    with assert_raises(contains="The frame has: region, amount"):
        _ = funnel(_cat_frame(), categories="region", values="nope")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
