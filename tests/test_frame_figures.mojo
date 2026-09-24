"""Named-column inputs for jointplot and pairplot figures (#743)."""

from dataframe import Column, DataFrame, Series
from dataviz import render_svg, jointplot, pairplot
from std.testing import TestSuite, assert_equal, assert_raises


def _frame() raises -> DataFrame:
    return DataFrame(
        [
            Series("height", Column[Float64]([1.0, 2.0, 3.0, 4.0])),
            Series("weight", Column[Float64]([2.0, 3.0, 5.0, 7.0])),
            Series("age", Column[Float64]([4.0, 3.0, 2.0, 1.0])),
        ]
    )


def test_jointplot_reads_named_columns_and_titles() raises:
    var df = _frame()
    var frame_svg = render_svg(
        jointplot(df, "height", "weight", width=400, height=400)
    ).to_string()
    var list_svg = render_svg(
        jointplot(
            [1.0, 2.0, 3.0, 4.0],
            [2.0, 3.0, 5.0, 7.0],
            width=400,
            height=400,
            x_title="height",
            y_title="weight",
        )
    ).to_string()
    assert_equal(frame_svg, list_svg)


def test_pairplot_reads_numeric_columns_in_requested_order() raises:
    var df = _frame()
    var names: List[String] = ["age", "height", "weight"]
    var frame_svg = render_svg(
        pairplot(df, names, cell_width=160, cell_height=120)
    ).to_string()
    var values: List[List[Float64]] = [
        [4.0, 3.0, 2.0, 1.0],
        [1.0, 2.0, 3.0, 4.0],
        [2.0, 3.0, 5.0, 7.0],
    ]
    var list_svg = render_svg(
        pairplot(values, names, cell_width=160, cell_height=120)
    ).to_string()
    assert_equal(frame_svg, list_svg)


def test_pairplot_requires_two_columns() raises:
    var names: List[String] = ["height"]
    with assert_raises(contains="at least two columns"):
        _ = pairplot(_frame(), names)


def test_jointplot_names_the_missing_column() raises:
    with assert_raises(contains="weightless"):
        _ = jointplot(_frame(), "height", "weightless")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
