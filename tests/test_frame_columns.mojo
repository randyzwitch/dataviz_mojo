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

from dataframe import Column, DataFrame, DataType, Series
from morrow import Morrow

from _test_helpers import _attr_values

from dataviz import (
    arc_diagram,
    area,
    bar,
    calendar_heatmap,
    candlestick,
    corrplot,
    dendrogram,
    ecdf,
    funnel,
    gantt,
    heatmap,
    histogram,
    kdeplot,
    pie,
    parallel,
    polar,
    quiver,
    rugplot,
    sankey,
    scatter3d,
    treemap,
    tricontour,
    tricontourf,
    waterfall,
)
from dataviz.core.missing import Missing
from dataviz.core.theme import Theme
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


def test_arc_diagram_edge_columns() raises:
    var sources: List[String] = ["alpha", "beta", "alpha"]
    var destinations: List[String] = ["beta", "gamma", "gamma"]
    var weights: List[Float64] = [1.0, 2.0, 3.0]
    var df = DataFrame(
        [
            Series("source", Column[String](sources.copy())),
            Series("destination", Column[String](destinations.copy())),
            Series("weight", Column[Float64](weights.copy())),
        ]
    )
    var by_frame = render_svg(
        arc_diagram(
            df,
            from_categories="source",
            to_categories="destination",
            values="weight",
            width=400,
            height=300,
        )
    ).to_string()
    var by_list = render_svg(
        arc_diagram(sources, destinations, weights, width=400, height=300)
    ).to_string()
    assert_equal(by_frame, by_list, "arc_diagram: same document")


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


# ---------------------------------------------------------------
# Tier 4: the flat-column functions the earlier tiers left behind
# (#743). Same rule as above -- frame call and list call, same bytes.


def _obs() -> List[Float64]:
    return [2.0, 4.0, 3.0, 5.0, 4.5, 6.0, 3.5, 5.5]


def _obs_frame() raises -> DataFrame:
    return DataFrame([Series("latency", Column[Float64](_obs()))])


def test_area_reads_two_numeric_columns() raises:
    var xs: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var ys: List[Float64] = [2.0, 4.0, 3.0, 5.0]
    var df = DataFrame(
        [
            Series("day", Column[Float64](xs.copy())),
            Series("revenue", Column[Float64](ys.copy())),
        ]
    )
    var by_frame = render_svg(
        area(df, x="day", y="revenue", width=360, height=300)
    ).to_string()
    var by_list = render_svg(
        area(xs, ys, width=360, height=300, x_title="day", y_title="revenue")
    ).to_string()
    assert_equal(by_frame, by_list, "area: same document")


def test_one_observation_column_ecdf_kde_and_rug() raises:
    # Three functions whose whole input is a single numeric column, so
    # the only thing to get wrong is which title the name defaults to.
    var df = _obs_frame()

    var ecdf_frame = render_svg(
        ecdf(df, values="latency", width=360, height=300)
    ).to_string()
    var ecdf_list = render_svg(
        ecdf(_obs(), width=360, height=300, x_title="latency")
    ).to_string()
    assert_equal(ecdf_frame, ecdf_list, "ecdf: same document")

    var kde_frame = render_svg(
        kdeplot(df, values="latency", width=360, height=300)
    ).to_string()
    var kde_list = render_svg(
        kdeplot(_obs(), width=360, height=300, x_title="latency")
    ).to_string()
    assert_equal(kde_frame, kde_list, "kdeplot: same document")

    var rug_frame = render_svg(
        rugplot(df, values="latency", width=360, height=300)
    ).to_string()
    var rug_list = render_svg(
        rugplot(_obs(), width=360, height=300, x_title="latency")
    ).to_string()
    assert_equal(rug_frame, rug_list, "rugplot: same document")


def test_kdeplot_keeps_its_own_flags_through_the_frame_overload() raises:
    # bandwidth/fill/rug are not columns; a generated overload can drop
    # one silently, and the chart still renders.
    var df = _obs_frame()
    var plain = render_svg(
        kdeplot(df, values="latency", width=360, height=300)
    ).to_string()
    var filled = render_svg(
        kdeplot(df, values="latency", fill=True, width=360, height=300)
    ).to_string()
    var with_rug = render_svg(
        kdeplot(df, values="latency", rug=True, width=360, height=300)
    ).to_string()
    var wider = render_svg(
        kdeplot(df, values="latency", bandwidth=2.0, width=360, height=300)
    ).to_string()
    assert_true(plain != filled, "fill=True changed nothing")
    assert_true(plain != with_rug, "rug=True changed nothing")
    assert_true(plain != wider, "bandwidth changed nothing")


def test_ecdf_complementary_survives_the_frame_overload() raises:
    var df = _obs_frame()
    var normal = render_svg(
        ecdf(df, values="latency", width=360, height=300)
    ).to_string()
    var complementary = render_svg(
        ecdf(df, values="latency", complementary=True, width=360, height=300)
    ).to_string()
    assert_true(normal != complementary, "complementary=True changed nothing")


def test_corrplot_computes_pearson_matrix_from_frame() raises:
    var df = DataFrame(
        [
            Series("x", Column[Float64]([1.0, 2.0, 3.0])),
            Series("reverse", Column[Float64]([3.0, 2.0, 1.0])),
            Series("curve", Column[Float64]([1.0, 0.0, 1.0])),
            Series("flat", Column[Float64]([4.0, 4.0, 4.0])),
        ]
    )
    var names: List[String] = ["x", "reverse", "curve"]
    var expected: List[List[Float64]] = [
        [1.0, -1.0, 0.0],
        [-1.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
    ]
    var by_frame = render_svg(
        corrplot(df, columns=names, width=360, height=300)
    ).to_string()
    var by_matrix = render_svg(
        corrplot(names, expected, width=360, height=300)
    ).to_string()
    assert_equal(by_frame, by_matrix, "frame computes the expected matrix")
    with assert_raises(contains='duplicate column "x"'):
        _ = corrplot(df, columns=["x", "x"])
    with assert_raises(contains='no column named "absent"'):
        _ = corrplot(df, columns=["x", "absent"])
    with assert_raises(
        contains='columns "x" and "flat": correlation is undefined'
    ):
        _ = corrplot(df, columns=["x", "flat"])


def test_tricontour_frame_levels_are_independent_of_rows() raises:
    var xs: List[Float64] = [0.0, 1.0, 2.0, 0.5, 1.5, 1.0]
    var ys: List[Float64] = [0.0, 0.0, 0.0, 1.0, 1.0, 2.0]
    var zs: List[Float64] = [1.0, 2.0, 1.5, 3.0, 2.5, 4.0]
    var levels: List[Float64] = [1.5, 2.5, 3.5]
    var df = DataFrame(
        [
            Series("x", Column[Float64](xs.copy())),
            Series("y", Column[Float64](ys.copy())),
            Series("depth", Column[Float64](zs.copy())),
        ]
    )

    var filled_frame = render_svg(
        tricontourf(
            df, x="x", y="y", z="depth", levels=levels, width=360, height=300
        )
    ).to_string()
    var filled_list = render_svg(
        tricontourf(xs, ys, zs, levels=levels, width=360, height=300)
    ).to_string()
    assert_equal(filled_frame, filled_list, "filled levels: same document")

    var lines_frame = render_svg(
        tricontour(
            df, x="x", y="y", z="depth", levels=levels, width=360, height=300
        )
    ).to_string()
    var lines_list = render_svg(
        tricontour(xs, ys, zs, levels=levels, width=360, height=300)
    ).to_string()
    assert_equal(lines_frame, lines_list, "line levels: same document")

    var automatic = render_svg(
        tricontourf(df, x="x", y="y", z="depth", width=360, height=300)
    ).to_string()
    assert_true(automatic != filled_frame, "explicit levels changed nothing")


def test_a_missing_column_names_the_function_that_was_called() raises:
    # The caller sees the name they typed, not a helper's.
    var df = _obs_frame()
    with assert_raises(contains='ecdf(): no column named "nope"'):
        _ = ecdf(df, values="nope")
    with assert_raises(contains='kdeplot(): no column named "nope"'):
        _ = kdeplot(df, values="nope")
    with assert_raises(contains='rugplot(): no column named "nope"'):
        _ = rugplot(df, values="nope")
    with assert_raises(contains='tricontourf(): no column named "nope"'):
        _ = tricontourf(df, x="latency", y="latency", z="nope")


def test_an_explicit_axis_title_beats_the_column_name() raises:
    var df = _obs_frame()
    var defaulted = render_svg(
        ecdf(df, values="latency", width=360, height=300)
    ).to_string()
    var overridden = render_svg(
        ecdf(
            df, values="latency", x_title="Latency (ms)", width=360, height=300
        )
    ).to_string()
    assert_true("latency" in defaulted, "column name did not become the title")
    assert_true("Latency (ms)" in overridden, "explicit x_title was ignored")


def test_bar_reads_date_and_datetime_columns_as_time() raises:
    var dates: List[Morrow] = [
        Morrow.get(2024, 3, 1),
        Morrow.get(2024, 3, 4),
        Morrow.get(2024, 3, 5),
    ]
    var values: List[Float64] = [10.0, 20.0, 15.0]
    var day_values: List[Int64] = [19783, 19786, 19787]
    var date_frame = DataFrame(
        [
            Series("day", Column[Int64](day_values.copy())).with_dtype(
                DataType.DATE
            ),
            Series("amount", Column[Float64](values.copy())),
        ]
    )
    var by_date = bar(date_frame, x="day", y="amount")
    assert_true(by_date._x_time, "date column uses a time axis")
    assert_equal(
        by_date._continuous.x[1] - by_date._continuous.x[0], 3.0 * 86400.0
    )
    var expected = render_svg(
        bar(dates, values, x_title="day", y_title="amount")
    ).to_string()
    assert_equal(
        render_svg(by_date).to_string(), expected, "date column matches list"
    )
    var millis: List[Int64] = [1709251200000, 1709510400000, 1709596800000]
    var stamp_frame = DataFrame(
        [
            Series("day", Column[Int64](millis.copy())).with_dtype(
                DataType.datetime("ms")
            ),
            Series("amount", Column[Float64](values.copy())),
        ]
    )
    assert_equal(
        render_svg(bar(stamp_frame, x="day", y="amount")).to_string(),
        expected,
        "datetime column matches list",
    )


def test_parallel_reads_named_metrics_in_row_order() raises:
    var df = DataFrame(
        [
            Series("model", Column[String](["A", "B", "C"])),
            Series("range", Column[Float64]([3.0, 7.0, 0.0])),
            Series("cost", Column[Float64]([7.0, 3.0, 10.0])),
        ]
    )
    var dims: List[String] = ["range", "cost"]
    var names: List[String] = ["A", "B", "C"]
    var rows: List[List[Float64]] = [[3.0, 7.0], [7.0, 3.0], [0.0, 10.0]]
    var from_frame = render_svg(
        parallel(df, dims=dims, row_name="model", width=400, height=300)
    ).to_string()
    var from_lists = render_svg(
        parallel(rows, dims, names, width=400, height=300)
    ).to_string()
    assert_equal(from_frame, from_lists, "one frame row becomes one polyline")


def test_parallel_missing_metric_breaks_a_line() raises:
    var df = DataFrame(
        [
            Series("model", Column[String](["A", "B"])),
            Series("a", Column[Float64]([2.0, 0.0])),
            Series("b", Column[Float64]([7.0, 8.0], [False, True])),
            Series("c", Column[Float64]([4.0, 6.0])),
            Series("d", Column[Float64]([5.0, 7.0])),
        ]
    )
    var dims: List[String] = ["a", "b", "c", "d"]
    var theme = Theme(show_legend=False, show_gridlines=False)
    var svg = render_svg(
        parallel(df, dims=dims, row_name="model", theme=theme)
    ).to_string()
    var paths = _attr_values(svg, "path", "d")
    assert_equal(len(paths), 2, "one path per row")
    assert_equal(paths[0].count("M"), 2, "missing b starts a new run")
    assert_equal(paths[0].count("L"), 1, "only c to d is joined")
    assert_equal(paths[1].count("M"), 1, "complete row stays connected")
    assert_equal(paths[1].count("L"), 3, "complete row has three links")
    with assert_raises(contains='column "b" has 1 missing value(s)'):
        _ = parallel(
            df,
            dims=dims,
            row_name="model",
            theme=Theme(missing=Missing.RAISE),
        )


def test_parallel_all_missing_row_has_no_path() raises:
    var df = DataFrame(
        [
            Series("model", Column[String](["A", "B"])),
            Series("a", Column[Float64]([2.0, 1.0], [False, True])),
            Series("b", Column[Float64]([3.0, 4.0], [False, True])),
        ]
    )
    var dims: List[String] = ["a", "b"]
    var svg = render_svg(
        parallel(
            df,
            dims=dims,
            row_name="model",
            theme=Theme(show_legend=False, show_gridlines=False),
        )
    ).to_string()
    assert_equal(
        len(_attr_values(svg, "path", "d")),
        1,
        "the row without observations cannot draw a line",
    )


def test_gantt_reads_temporal_start_and_end_columns() raises:
    var tasks: List[String] = ["Build", "Ship"]
    var start_days: List[Int64] = [19783, 19786]
    var end_days: List[Int64] = [19786, 19787]
    var df = DataFrame(
        [
            Series("task", Column[String](tasks.copy())),
            Series("start", Column[Int64](start_days.copy())).with_dtype(
                DataType.DATE
            ),
            Series("end", Column[Int64](end_days.copy())).with_dtype(
                DataType.DATE
            ),
        ]
    )
    var expected = render_svg(
        gantt(
            tasks,
            [Morrow.get(2024, 3, 1), Morrow.get(2024, 3, 4)],
            [Morrow.get(2024, 3, 4), Morrow.get(2024, 3, 5)],
            x_title="start",
        )
    ).to_string()
    var from_frame = gantt(df, categories="task", start="start", end="end")
    assert_true(from_frame._x_time, "temporal columns use a time axis")
    assert_equal(
        render_svg(from_frame).to_string(), expected, "date columns match lists"
    )
    var mismatch = DataFrame(
        [
            Series("task", Column[String](tasks.copy())),
            Series("start", Column[Int64](start_days.copy())).with_dtype(
                DataType.DATE
            ),
            Series("end", Column[Float64]([1.0, 2.0])),
        ]
    )
    with assert_raises(contains="both be temporal or both numeric"):
        _ = gantt(mismatch, categories="task", start="start", end="end")


def test_candlestick_reads_date_and_datetime_columns_as_time() raises:
    var dates: List[Morrow] = [
        Morrow.get(2024, 3, 1),
        Morrow.get(2024, 3, 4),
        Morrow.get(2024, 3, 5),
    ]
    var days: List[Int64] = [19783, 19786, 19787]
    var o: List[Float64] = [10.0, 11.0, 12.0]
    var h: List[Float64] = [12.0, 13.0, 14.0]
    var l: List[Float64] = [9.0, 10.0, 11.0]
    var c: List[Float64] = [11.0, 12.0, 13.0]
    var df = DataFrame(
        [
            Series("day", Column[Int64](days.copy())).with_dtype(DataType.DATE),
            Series("open", Column[Float64](o.copy())),
            Series("high", Column[Float64](h.copy())),
            Series("low", Column[Float64](l.copy())),
            Series("close", Column[Float64](c.copy())),
        ]
    )
    var expected = render_svg(
        candlestick(dates, o, h, l, c, x_title="day")
    ).to_string()
    var from_frame = candlestick(
        df, categories="day", open="open", high="high", low="low", close="close"
    )
    assert_true(from_frame._x_time, "date column uses a time axis")
    assert_equal(
        render_svg(from_frame).to_string(), expected, "date column matches list"
    )
    var micros: List[Int64] = [
        1709251200000000,
        1709510400000000,
        1709596800000000,
    ]
    var stamps = DataFrame(
        [
            Series("day", Column[Int64](micros.copy())).with_dtype(
                DataType.datetime("us")
            ),
            Series("open", Column[Float64](o.copy())),
            Series("high", Column[Float64](h.copy())),
            Series("low", Column[Float64](l.copy())),
            Series("close", Column[Float64](c.copy())),
        ]
    )
    assert_equal(
        render_svg(
            candlestick(
                stamps,
                categories="day",
                open="open",
                high="high",
                low="low",
                close="close",
            )
        ).to_string(),
        expected,
        "datetime column matches list",
    )


def test_dendrogram_clusters_frame_rows_by_named_features() raises:
    var frame = DataFrame(
        [
            Series("name", Column[String](["A", "B", "C"])),
            Series("f1", Column[Float64]([0.0, 1.0, 10.0])),
            Series("f2", Column[Float64]([0.0, 1.0, 10.0])),
        ]
    )
    var by_frame = render_svg(
        dendrogram(
            frame,
            features=["f1", "f2"],
            labels="name",
            width=360,
            height=260,
        )
    ).to_string()
    var by_rows = render_svg(
        dendrogram(
            [[0.0, 0.0], [1.0, 1.0], [10.0, 10.0]],
            labels=["A", "B", "C"],
            width=360,
            height=260,
        )
    ).to_string()
    assert_equal(by_frame, by_rows, "frame rows match list rows")
    with assert_raises(contains="at least one column"):
        _ = dendrogram(frame, features=List[String]())
    with assert_raises(contains='no column named "absent"'):
        _ = dendrogram(frame, features=["absent"])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
