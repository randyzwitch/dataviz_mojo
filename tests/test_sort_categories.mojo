"""`Chart.sort_categories()` (#843): reorder a categorical chart's
categories by value, by label, or by a named list, with every
per-category column moving together.

Checked on the stored data, which is what every renderer reads, and on
one rendered SVG, to see a sorted chart draw the same bytes as the same
data passed in sorted order.
"""

from std.math import nan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from dataviz import CategoryOrder, render, render_svg
from dataviz.plot import Plot


def _cats() -> List[String]:
    return ["north", "east", "south", "west"]


def _vals() -> List[Float64]:
    return [3.0, 7.0, 1.0, 7.0]


def test_value_descending_is_stable_on_ties() raises:
    var c = (
        Plot()
        .mark_bar()
        .encode_categorical(_cats(), _vals())
        .sort_categories(CategoryOrder.VALUE_DESCENDING)
    )
    var want: List[String] = ["east", "west", "north", "south"]
    assert_true(c.mark.categorical.x == want)
    var want_y: List[Float64] = [7.0, 7.0, 3.0, 1.0]
    assert_true(c.mark.continuous.y == want_y)


def test_value_ascending_and_labels() raises:
    var up = (
        Plot()
        .mark_lollipop()
        .encode_categorical(_cats(), _vals())
        .sort_categories(CategoryOrder.VALUE_ASCENDING)
    )
    var want_up: List[String] = ["south", "north", "east", "west"]
    assert_true(up.mark.categorical.x == want_up)
    var az = (
        Plot()
        .mark_bar()
        .encode_categorical(_cats(), _vals())
        .sort_categories(CategoryOrder.LABEL_ASCENDING)
    )
    var want_az: List[String] = ["east", "north", "south", "west"]
    assert_true(az.mark.categorical.x == want_az)
    var za = (
        Plot()
        .mark_bar()
        .encode_categorical(_cats(), _vals())
        .sort_categories(CategoryOrder.LABEL_DESCENDING)
    )
    var want_za: List[String] = ["west", "south", "north", "east"]
    assert_true(za.mark.categorical.x == want_za)


def test_error_bars_follow_their_category() raises:
    var err: List[Float64] = [0.3, 0.7, 0.1, 0.9]
    var c = (
        Plot()
        .mark_bar()
        .encode_categorical(_cats(), _vals(), y_err=err)
        .sort_categories(CategoryOrder.VALUE_ASCENDING)
    )
    var want: List[Float64] = [0.1, 0.3, 0.7, 0.9]
    assert_true(c.mark.y_err.symmetric == want)


def test_a_missing_value_sorts_last_both_ways() raises:
    var missing_value = nan[DType.float64]()
    var vals: List[Float64] = [2.0, missing_value, 1.0]
    var cats: List[String] = ["a", "b", "c"]
    var up = (
        Plot()
        .mark_bar()
        .encode_categorical(cats, vals)
        .sort_categories(CategoryOrder.VALUE_ASCENDING)
    )
    var want_up: List[String] = ["c", "a", "b"]
    assert_true(up.mark.categorical.x == want_up)
    var down = (
        Plot()
        .mark_bar()
        .encode_categorical(cats, vals)
        .sort_categories(CategoryOrder.VALUE_DESCENDING)
    )
    var want_down: List[String] = ["a", "c", "b"]
    assert_true(down.mark.categorical.x == want_down)


def test_a_named_order() raises:
    var order: List[String] = ["west", "north", "east", "south"]
    var c = (
        Plot()
        .mark_funnel()
        .encode_categorical(_cats(), _vals())
        .sort_categories(order)
    )
    assert_true(c.mark.categorical.x == order)
    var want_y: List[Float64] = [7.0, 3.0, 7.0, 1.0]
    assert_true(c.mark.continuous.y == want_y)


def test_a_sorted_chart_draws_what_sorted_input_draws() raises:
    var sorted_cats: List[String] = ["east", "west", "north", "south"]
    var sorted_vals: List[Float64] = [7.0, 7.0, 3.0, 1.0]
    var by_input = render_svg(
        Plot().mark_bar().encode_categorical(sorted_cats, sorted_vals)
    ).to_string()
    var by_sort = render_svg(
        Plot()
        .mark_bar()
        .encode_categorical(_cats(), _vals())
        .sort_categories(CategoryOrder.VALUE_DESCENDING)
    ).to_string()
    assert_equal(by_input, by_sort)


def test_every_categorical_mark_sorts() raises:
    var order = CategoryOrder.VALUE_DESCENDING
    _ = render(
        Plot()
        .mark_arc()
        .encode_categorical(_cats(), _vals())
        .sort_categories(order)
    )
    _ = render(
        Plot()
        .mark_nightingale()
        .encode_categorical(_cats(), _vals())
        .sort_categories(order)
    )
    _ = render(
        Plot()
        .mark_polar_bar()
        .encode_categorical(_cats(), _vals())
        .sort_categories(order)
    )
    _ = render(
        Plot()
        .mark_radialbar()
        .encode_categorical(_cats(), _vals())
        .sort_categories(order)
    )
    _ = render(
        Plot()
        .mark_pointplot()
        .encode_categorical(_cats(), _vals())
        .sort_categories(order)
    )


def test_refusals() raises:
    with assert_raises(contains="this chart has no categories yet"):
        _ = Plot().mark_bar().sort_categories(CategoryOrder.VALUE_ASCENDING)
    var missing: List[String] = ["west", "north", "east"]
    with assert_raises(contains='does not name "south"'):
        _ = (
            Plot()
            .mark_bar()
            .encode_categorical(_cats(), _vals())
            .sort_categories(missing)
        )
    var twice: List[String] = ["west", "north", "east", "east"]
    with assert_raises(contains='"east" is named more than once'):
        _ = (
            Plot()
            .mark_bar()
            .encode_categorical(_cats(), _vals())
            .sort_categories(twice)
        )
    var typo: List[String] = ["west", "north", "east", "sooth"]
    with assert_raises(contains='"sooth" is not one of this chart'):
        _ = (
            Plot()
            .mark_bar()
            .encode_categorical(_cats(), _vals())
            .sort_categories(typo)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
