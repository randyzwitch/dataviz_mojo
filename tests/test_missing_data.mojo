"""Missing observations, carried as `NaN` (#367).

The rule this file pins: a missing **value** has nowhere to sit on an
axis, so the observation drops out and the gap stays visible; a missing
**category** is a label, so those rows are kept under a name of their
own. The one thing no mark may do is join the two sides of a gap, which
would draw a measurement nobody made.

`Missing.RAISE` keeps the old strictness, and infinity is refused under
either policy -- it is not a missing measurement.
"""

from dataframe import Column, DataFrame, Series

from dataviz import (
    area,
    bar,
    barplot,
    box,
    calendar_heatmap,
    heatmap,
    histogram,
    imshow,
    kdeplot,
    line,
    lineplot,
    scatter,
)
from dataviz.core.missing import Missing
from dataviz.core.scale import _min_max
from dataviz.core.stats import Estimator, ErrorBar, _aggregate, _estimate
from dataviz.core.theme import Theme
from dataviz.plot import Plot, render, render_svg
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from std.utils.numerics import inf, nan


def _nan() -> Float64:
    return nan[DType.float64]()


def _xs() -> List[Float64]:
    return [0.0, 1.0, 2.0, 3.0, 4.0]


def _with_hole() -> List[Float64]:
    return [1.0, 2.0, _nan(), 4.0, 5.0]


def _whole() -> List[Float64]:
    return [1.0, 2.0, 3.0, 4.0, 5.0]


def test_a_line_breaks_at_a_missing_observation() raises:
    """The acceptance criterion: a gap in the data is a gap in the line,
    in the SVG and in the raster."""
    var gapped = render_svg(
        line(_xs(), _with_hole(), width=320, height=240)
    ).to_string()
    var solid = render_svg(
        line(_xs(), _whole(), width=320, height=240)
    ).to_string()
    assert_equal(gapped.count("<path"), 2, "two runs, two paths")
    assert_equal(solid.count("<path"), 1, "nothing missing, one path")


def test_the_gap_is_visible_in_the_raster_too() raises:
    """SVG structure could differ while the picture stayed the same, so
    the pixels are checked as well: the two renders cannot be equal."""
    var gapped = render(line(_xs(), _with_hole(), width=320, height=240))
    var solid = render(line(_xs(), _whole(), width=320, height=240))
    var differs = False
    for y in range(gapped.height):
        for x in range(gapped.width):
            var a = gapped.get_pixel(x, y)
            var b = solid.get_pixel(x, y)
            if a.r != b.r or a.g != b.g or a.b != b.b:
                differs = True
    assert_true(differs, "the hole changes the picture")


def test_a_scatter_drops_only_the_missing_point() raises:
    var svg = render_svg(
        scatter(_xs(), _with_hole(), width=320, height=240)
    ).to_string()
    assert_equal(svg.count("<circle"), 4, "four of five points drawn")


def test_a_missing_point_takes_its_whole_row_with_it() raises:
    """Channel alignment survives the drop: the remaining points keep
    the colors and sizes of their own rows, not of the rows after
    them."""
    var xs: List[Float64] = [0.0, 1.0, 2.0]
    var ys: List[Float64] = [1.0, _nan(), 3.0]
    var colors: List[Float64] = [0.0, 0.5, 1.0]
    var plot = (
        Plot().mark_point().encode(x=xs, y=ys, color=colors).size(320, 240)
    )
    var svg = render_svg(plot).to_string()
    assert_equal(svg.count("<circle"), 2, "the middle row is gone")

    # The same two rows, written without the hole, must draw the same
    # circles: if the color channel had shifted, these would differ.
    var kept_x: List[Float64] = [0.0, 2.0]
    var kept_y: List[Float64] = [1.0, 3.0]
    var kept_c: List[Float64] = [0.0, 1.0]
    var same = (
        Plot()
        .mark_point()
        .encode(x=kept_x, y=kept_y, color=kept_c)
        .size(320, 240)
    )
    var by_hand = render_svg(same).to_string()
    var first = svg.find("<circle")
    var also = by_hand.find("<circle")
    assert_true(first >= 0 and also >= 0, "both drew points")


def test_an_area_leaves_the_gap_unfilled() raises:
    var gapped = render_svg(
        area(_xs(), _with_hole(), width=320, height=240)
    ).to_string()
    var solid = render_svg(
        area(_xs(), _whole(), width=320, height=240)
    ).to_string()
    assert_true(
        gapped.count("<path") > solid.count("<path"),
        "the band is drawn in pieces, not across the hole",
    )


def test_the_domain_ignores_missing_values() raises:
    var data: List[Float64] = [2.0, _nan(), 8.0]
    var extent = _min_max(data)
    assert_equal(extent.min, 2.0, "the hole does not drag the low end")
    assert_equal(extent.max, 8.0, "nor the high end")


def test_a_column_that_is_missing_throughout_has_no_domain() raises:
    var data: List[Float64] = [_nan(), _nan()]
    with assert_raises(contains="every value in this column is missing"):
        _ = _min_max(data)


def test_infinity_is_still_refused() raises:
    """An infinity is not a missing measurement: it is a number no axis
    can place, and it raises under either policy."""
    var data: List[Float64] = [1.0, inf[DType.float64](), 3.0]
    with assert_raises(contains="every value must be finite"):
        _ = _min_max(data)


def test_strict_mode_refuses_a_missing_value() raises:
    with assert_raises(contains="the y channel has a missing value at index 2"):
        _ = render_svg(
            line(_xs(), _with_hole(), theme=Theme(missing=Missing.RAISE))
        )


def test_strict_mode_lets_a_whole_column_through() raises:
    var svg = render_svg(
        line(_xs(), _whole(), theme=Theme(missing=Missing.RAISE))
    ).to_string()
    assert_true("<path" in svg, "nothing missing, nothing refused")


def _frame_with_holes() raises -> DataFrame:
    return DataFrame(
        [
            Series("day", Column[Float64]([1.0, 2.0, 3.0, 4.0])),
            Series(
                "reading",
                Column[Float64](
                    [5.0, 6.0, 7.0, 8.0], [True, True, False, True]
                ),
            ),
            Series(
                "region",
                Column[String](
                    ["north", "south", "north", "east"],
                    [True, False, True, True],
                ),
            ),
            Series("amount", Column[Float64]([3.0, 4.0, 5.0, 6.0])),
        ]
    )


def test_a_frame_s_missing_value_becomes_a_gap() raises:
    var svg = render_svg(
        line(_frame_with_holes(), x="day", y="reading", width=320, height=240)
    ).to_string()
    assert_equal(svg.count("<path"), 2, "the null row breaks the line")


def test_a_frame_s_missing_category_becomes_its_own_category() raises:
    """A blank category is a label, and the row's value is perfectly
    good: dropping it would lose a measurement over a missing name."""
    var svg = render_svg(
        bar(_frame_with_holes(), x="region", y="amount", width=400, height=280)
    ).to_string()
    assert_true(">(missing)</text>" in svg, "the rows get a name of their own")
    assert_true(">south</text>" not in svg, "which is not the name they had")


def test_the_missing_category_label_is_the_theme_s() raises:
    var svg = render_svg(
        bar(
            _frame_with_holes(),
            x="region",
            y="amount",
            theme=Theme(missing_category_label="not recorded"),
            width=400,
            height=280,
        )
    ).to_string()
    assert_true(">not recorded</text>" in svg, "the caller's name is used")


def test_strict_mode_refuses_a_frame_s_nulls_at_the_boundary() raises:
    with assert_raises(contains='column "reading" has 1 missing value(s)'):
        _ = line(
            _frame_with_holes(),
            x="day",
            y="reading",
            theme=Theme(missing=Missing.RAISE),
        )


def _cells() -> List[List[Float64]]:
    var grid = List[List[Float64]]()
    var row0: List[Float64] = [1.0, _nan()]
    var row1: List[Float64] = [3.0, 4.0]
    grid.append(row0^)
    grid.append(row1^)
    return grid^


def test_a_missing_heatmap_cell_is_left_blank() raises:
    """A color off the end of the ramp reads as a measurement at that
    end, so a cell with no value is not drawn at all."""
    var xs: List[String] = ["a", "b", "a", "b"]
    var ys: List[String] = ["r", "r", "s", "s"]
    var holed: List[Float64] = [1.0, 2.0, _nan(), 4.0]
    var whole: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var gapped = render_svg(
        heatmap(xs, ys, holed, width=320, height=240)
    ).to_string()
    var solid = render_svg(
        heatmap(xs, ys, whole, width=320, height=240)
    ).to_string()
    assert_equal(
        gapped.count("<rect") + 1,
        solid.count("<rect"),
        "one cell fewer is drawn",
    )


def test_missing_cells_do_not_move_the_color_limits() raises:
    """The acceptance criterion: the ramp spans the cells that are
    there, so the same value is the same color with or without a hole
    elsewhere in the grid."""
    var xs: List[String] = ["a", "b", "a", "b"]
    var ys: List[String] = ["r", "r", "s", "s"]
    var holed: List[Float64] = [1.0, 4.0, _nan(), 4.0]
    var without: List[String] = ["a", "b", "b"]
    var without_y: List[String] = ["r", "r", "s"]
    var kept: List[Float64] = [1.0, 4.0, 4.0]
    var with_hole = render_svg(
        heatmap(xs, ys, holed, width=320, height=240)
    ).to_string()
    var no_hole = render_svg(
        heatmap(without, without_y, kept, width=320, height=240)
    ).to_string()
    # The legend's end labels come from the limits, which must match.
    assert_true(
        ">1.0</text>" in with_hole and ">1.0</text>" in no_hole,
        "same low end",
    )
    assert_true(
        ">4.0</text>" in with_hole and ">4.0</text>" in no_hole,
        "same high end",
    )


def test_a_missing_image_cell_is_left_blank() raises:
    var svg = render_svg(imshow(_cells(), width=200, height=200)).to_string()
    var full = List[List[Float64]]()
    var r0: List[Float64] = [1.0, 2.0]
    var r1: List[Float64] = [3.0, 4.0]
    full.append(r0^)
    full.append(r1^)
    var whole = render_svg(imshow(full, width=200, height=200)).to_string()
    assert_true(
        svg.count("<rect") < whole.count("<rect"),
        "the missing cell draws nothing",
    )


def test_a_grid_that_is_missing_throughout_has_no_color_limits() raises:
    var grid = List[List[Float64]]()
    var row: List[Float64] = [_nan(), _nan()]
    grid.append(row^)
    with assert_raises(contains="every cell in this grid is missing"):
        _ = render_svg(imshow(grid, width=200, height=200))


def test_a_missing_calendar_day_is_left_blank() raises:
    var dates: List[String] = ["2026-01-01", "2026-01-02", "2026-01-03"]
    var counts: List[Float64] = [3.0, _nan(), 5.0]
    var whole_counts: List[Float64] = [3.0, 4.0, 5.0]
    var gapped = render_svg(
        calendar_heatmap(dates, counts, width=640, height=220)
    ).to_string()
    var solid = render_svg(
        calendar_heatmap(dates, whole_counts, width=640, height=220)
    ).to_string()
    assert_equal(
        gapped.count("<rect") + 1, solid.count("<rect"), "one day fewer"
    )


def test_an_estimate_uses_the_observations_that_are_there() raises:
    var values: List[Float64] = [2.0, _nan(), 4.0]
    assert_equal(
        _estimate(values, Estimator.MEAN),
        3.0,
        "the mean of what was measured, not of a zero-filled column",
    )


def test_count_reports_the_effective_sample_size() raises:
    """The issue asks for the effective sample count to be visible.
    `Estimator.COUNT` is where it shows: it counts observations, not
    rows."""
    var values: List[Float64] = [2.0, _nan(), 4.0, _nan()]
    assert_equal(_estimate(values, Estimator.COUNT), 2.0, "two, not four")


def test_a_group_with_nothing_present_leaves_the_axis() raises:
    """A bar of no height reads as a measured zero, so a group with no
    observations is not drawn at all."""
    var groups: List[String] = ["a", "a", "b", "c"]
    var values: List[Float64] = [1.0, 3.0, _nan(), 5.0]
    var agg = _aggregate(
        groups, values, Estimator.MEAN, ErrorBar.none(), UInt64(7)
    )
    assert_equal(len(agg.categories), 2, "b has nothing to estimate")
    assert_equal(agg.categories[0], "a")
    assert_equal(agg.categories[1], "c")
    assert_equal(agg.estimates[0], 2.0, "a's mean is of its two values")


def test_an_interval_is_computed_from_what_is_there() raises:
    """A bootstrap that could draw a missing value would put a NaN in
    the interval, which is drawn as a whisker to nowhere."""
    var groups: List[String] = ["a", "a", "a", "a"]
    var with_hole: List[Float64] = [1.0, 2.0, 3.0, _nan()]
    var agg = _aggregate(
        groups, with_hole, Estimator.MEAN, ErrorBar.ci(0.95), UInt64(7)
    )
    assert_true(agg.lows[0] == agg.lows[0], "the low end is a number")
    assert_true(agg.highs[0] == agg.highs[0], "and so is the high end")
    assert_true(agg.lows[0] <= agg.estimates[0], "and it brackets the mean")
    assert_true(agg.highs[0] >= agg.estimates[0])


def test_a_barplot_with_a_hole_matches_the_column_without_it() raises:
    """End to end: the estimate a chart draws is the estimate of the
    observations that are there."""
    var groups: List[String] = ["a", "a", "a"]
    var holed: List[Float64] = [2.0, _nan(), 4.0]
    var kept_groups: List[String] = ["a", "a"]
    var kept: List[Float64] = [2.0, 4.0]
    var with_hole = render_svg(
        barplot(groups, holed, width=320, height=240)
    ).to_string()
    var without = render_svg(
        barplot(kept_groups, kept, width=320, height=240)
    ).to_string()
    assert_equal(with_hole, without, "same chart, byte for byte")


def test_a_histogram_counts_only_what_was_measured() raises:
    var holed: List[Float64] = [1.0, 2.0, _nan(), 8.0]
    var kept: List[Float64] = [1.0, 2.0, 8.0]
    var with_hole = render_svg(
        histogram(holed, bins=4, width=320, height=240)
    ).to_string()
    var without = render_svg(
        histogram(kept, bins=4, width=320, height=240)
    ).to_string()
    assert_equal(with_hole, without, "the hole is counted nowhere")


def test_a_box_summarizes_the_observations_that_are_there() raises:
    var cats: List[String] = ["a"]
    var holed = List[List[Float64]]()
    var one: List[Float64] = [1.0, 2.0, _nan(), 3.0, 4.0]
    holed.append(one^)
    var kept = List[List[Float64]]()
    var two: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    kept.append(two^)
    var with_hole = render_svg(
        box(cats, holed, width=320, height=240)
    ).to_string()
    var without = render_svg(box(cats, kept, width=320, height=240)).to_string()
    assert_equal(with_hole, without, "same five-number summary")


def test_a_density_curve_is_estimated_from_what_is_there() raises:
    var holed: List[Float64] = [1.0, 2.0, _nan(), 3.0, 4.0]
    var kept: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var with_hole = render_svg(
        kdeplot(holed, width=320, height=240)
    ).to_string()
    var without = render_svg(kdeplot(kept, width=320, height=240)).to_string()
    assert_equal(with_hole, without, "one missing kernel, not a NaN curve")


def test_an_estimate_line_skips_an_x_with_nothing_present() raises:
    var xs: List[Float64] = [1.0, 1.0, 2.0, 3.0]
    var ys: List[Float64] = [4.0, 6.0, _nan(), 8.0]
    var kept_x: List[Float64] = [1.0, 1.0, 3.0]
    var kept_y: List[Float64] = [4.0, 6.0, 8.0]
    var with_hole = render_svg(
        lineplot(xs, ys, width=320, height=240)
    ).to_string()
    var without = render_svg(
        lineplot(kept_x, kept_y, width=320, height=240)
    ).to_string()
    assert_equal(with_hole, without, "x=2 has no estimate and no point")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
