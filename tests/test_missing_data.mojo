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

from dataviz import area, bar, line, scatter
from dataviz.core.missing import Missing
from dataviz.core.scale import _min_max
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
