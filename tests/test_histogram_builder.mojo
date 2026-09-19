"""`mark_histogram().encode_histogram(data)` works, and draws what
`histogram()` draws (#698).

The chain reads as the obvious way to build a histogram, and it raised:
`encode_histogram()` only knew the categorical `mark_bar()` form, whose
bars are range labels, and the numeric mark wanted precomputed bins
through `encode_histogram_bins()`. The names promised a pairing the API
refused.

The acceptance criterion is agreement with the one-call form, so that is
what every test here asserts: same data, same options, same pixels. A
builder chart that merely rendered would pass a weaker test while
padding its axis differently, and a reader would see two histograms of
the same data that do not line up.
"""

from std.testing import TestSuite, assert_raises

from _test_helpers import _assert_same_canvas
from dataviz.binned.histogram import BinRule, HistStat, histogram
from dataviz.plot import Plot, render


def _data() -> List[Float64]:
    var v = List[Float64]()
    var seed = 20260918
    for _ in range(300):
        seed = (seed * 1103515245 + 12345) % 2147483648
        var a = Float64(seed % 10000) / 1000.0
        seed = (seed * 1103515245 + 12345) % 2147483648
        var b = Float64(seed % 10000) / 1000.0
        v.append(a + b)  # triangular, so the bars have a shape
    return v^


def _weights(n: Int) -> List[Float64]:
    var w = List[Float64]()
    for i in range(n):
        w.append(Float64(i % 3) + 0.5)
    return w^


def test_the_builder_chain_draws_what_histogram_draws() raises:
    var d = _data()
    _assert_same_canvas(
        render(histogram(d, 12)),
        render(Plot().mark_histogram().encode_histogram(d, 12)),
        "mark_histogram().encode_histogram(d, 12) against histogram(d, 12)",
    )


def test_a_bin_rule_agrees_too() raises:
    var d = _data()
    _assert_same_canvas(
        render(histogram(d, BinRule.AUTO)),
        render(Plot().mark_histogram().encode_histogram(d, BinRule.AUTO)),
        "the BinRule overloads disagree",
    )


def test_weights_stat_and_cumulative_agree() raises:
    # The normalization options are where two implementations drift, so
    # all three at once, on a stat whose heights depend on bin width.
    var d = _data()
    var w = _weights(len(d))
    _assert_same_canvas(
        render(
            histogram(d, 10, weights=w, stat=HistStat.DENSITY, cumulative=True)
        ),
        render(
            Plot()
            .mark_histogram()
            .encode_histogram(
                d, 10, weights=w, stat=HistStat.DENSITY, cumulative=True
            )
        ),
        "weighted cumulative density disagrees",
    )


def test_horizontal_agrees() raises:
    var d = _data()
    _assert_same_canvas(
        render(histogram(d, 12, horizontal=True)),
        render(Plot().mark_histogram(horizontal=True).encode_histogram(d, 12)),
        "the horizontal forms disagree",
    )


def test_a_domain_set_first_is_not_overwritten() raises:
    # encode_histogram pins the bin range, as histogram() does. A domain
    # the caller set before it must still win, the way it would after.
    var d = _data()
    var before = render(
        Plot()
        .mark_histogram()
        .scale_x_domain(-5.0, 30.0)
        .encode_histogram(d, 12)
    )
    var after = render(
        Plot()
        .mark_histogram()
        .encode_histogram(d, 12)
        .scale_x_domain(-5.0, 30.0)
    )
    _assert_same_canvas(
        before, after, "a domain set before encode_histogram was clobbered"
    )


def test_the_categorical_bar_form_still_works() raises:
    # mark_bar() keeps its range-labeled bars. Nothing existing changes.
    _ = render(Plot().mark_bar().encode_histogram(_data(), 8))


def test_numeric_options_on_the_bar_form_raise() raises:
    with assert_raises(contains="call mark_histogram() instead"):
        _ = (
            Plot()
            .mark_bar()
            .encode_histogram(_data(), 8, stat=HistStat.DENSITY)
        )


def test_the_wrong_mark_names_both_right_ones() raises:
    with assert_raises(contains="mark_histogram() or mark_bar()"):
        _ = Plot().mark_line().encode_histogram(_data(), 8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
