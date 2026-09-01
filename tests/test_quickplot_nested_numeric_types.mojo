"""Tests for the `DType`-generic overloads added to every quickplot
convenience function whose data is a *nested* `List[List[Float64]]`
column -- `grouped_bar()`/`stacked_bar()`/`bump()`/`streamgraph()`
(share `Plot.encode_grouped_bar()`), `beeswarm()`/`ridgeline()`/
`violin()`/`box()` (share `Plot.encode_distribution()`/`encode_
boxplot()`), `marimekko()`, `radar()`, `parallel()`, `polar_series()`.
The follow-up #158's own tracking issue called out as harder than the
flat-list case (`test_quickplot_numeric_types.mojo`) -- one test per
function: calling it with `List[List[Int]]` data renders byte-for-byte
identically to calling it with the equivalent `List[List[Float64]]`
data, via the new `_materialize_nested_scalar_list` (array_like.mojo).

Also covers `radar()`'s other, independent `DType`-generic axis (#173):
`max_values` is a flat `List[Float64]`, generalized separately from
`series_values`' own nested axis above -- the two can't be generic
together in one call (see `encode_radar()`'s own docstring for why),
so this is its own dedicated test, not folded into the nested one.

`corrplot()`/`parallel()`'s own example data stayed `Float64`
(correlations, decimal-valued real-world stats) -- not swept in the
Cookbook/docstring sense, but still covered here with synthetic whole-
number data to prove the overload itself works correctly regardless.
"""

from std.testing import assert_equal, TestSuite

from dataviz_mojo import (
    beeswarm,
    box,
    bump,
    corrplot,
    grouped_bar,
    marimekko,
    parallel,
    polar_series,
    radar,
    ridgeline,
    stacked_bar,
    streamgraph,
    violin,
)
from dataviz_mojo.plot import render_svg


def test_grouped_bar_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["Q1", "Q2"]
    var names: List[String] = ["North", "South"]
    var vi: List[List[Int]] = [[42, 48], [30, 35]]
    var vf: List[List[Float64]] = [[42.0, 48.0], [30.0, 35.0]]
    assert_equal(
        render_svg(grouped_bar(cats, names, vi)).to_string(),
        render_svg(grouped_bar(cats, names, vf)).to_string(),
    )


def test_stacked_bar_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["Q1", "Q2"]
    var names: List[String] = ["North", "South"]
    var vi: List[List[Int]] = [[42, 48], [30, 35]]
    var vf: List[List[Float64]] = [[42.0, 48.0], [30.0, 35.0]]
    assert_equal(
        render_svg(stacked_bar(cats, names, vi)).to_string(),
        render_svg(stacked_bar(cats, names, vf)).to_string(),
    )


def test_bump_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["2020", "2021"]
    var names: List[String] = ["Python", "Rust"]
    var vi: List[List[Int]] = [[85, 90], [92, 88]]
    var vf: List[List[Float64]] = [[85.0, 90.0], [92.0, 88.0]]
    assert_equal(
        render_svg(bump(cats, names, vi)).to_string(), render_svg(bump(cats, names, vf)).to_string()
    )


def test_streamgraph_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["2020", "2021"]
    var names: List[String] = ["Rock", "Pop"]
    var vi: List[List[Int]] = [[30, 40], [45, 35]]
    var vf: List[List[Float64]] = [[30.0, 40.0], [45.0, 35.0]]
    assert_equal(
        render_svg(streamgraph(cats, names, vi)).to_string(),
        render_svg(streamgraph(cats, names, vf)).to_string(),
    )


def test_beeswarm_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B"]
    var vi: List[List[Int]] = [[72, 75, 78], [65, 70, 72]]
    var vf: List[List[Float64]] = [[72.0, 75.0, 78.0], [65.0, 70.0, 72.0]]
    assert_equal(render_svg(beeswarm(cats, vi)).to_string(), render_svg(beeswarm(cats, vf)).to_string())


def test_ridgeline_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B"]
    var vi: List[List[Int]] = [[68, 70, 72], [78, 80, 82]]
    var vf: List[List[Float64]] = [[68.0, 70.0, 72.0], [78.0, 80.0, 82.0]]
    assert_equal(render_svg(ridgeline(cats, vi)).to_string(), render_svg(ridgeline(cats, vf)).to_string())


def test_violin_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B"]
    var vi: List[List[Int]] = [[72, 75, 78], [65, 70, 72]]
    var vf: List[List[Float64]] = [[72.0, 75.0, 78.0], [65.0, 70.0, 72.0]]
    assert_equal(render_svg(violin(cats, vi)).to_string(), render_svg(violin(cats, vf)).to_string())


def test_box_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B"]
    var vi: List[List[Int]] = [[72, 75, 78, 80], [60, 65, 68, 70]]
    var vf: List[List[Float64]] = [[72.0, 75.0, 78.0, 80.0], [60.0, 65.0, 68.0, 70.0]]
    assert_equal(render_svg(box(cats, vi)).to_string(), render_svg(box(cats, vf)).to_string())


def test_corrplot_accepts_nested_list_int_matching_list_float64() raises:
    var vars: List[String] = ["A", "B"]
    var mi: List[List[Int]] = [[1, 0], [0, 1]]
    var mf: List[List[Float64]] = [[1.0, 0.0], [0.0, 1.0]]
    assert_equal(render_svg(corrplot(vars, mi)).to_string(), render_svg(corrplot(vars, mf)).to_string())


def test_marimekko_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B"]
    var subcats: List[String] = ["X", "Y"]
    var vi: List[List[Int]] = [[5, 20], [30, 35]]
    var vf: List[List[Float64]] = [[5.0, 20.0], [30.0, 35.0]]
    assert_equal(
        render_svg(marimekko(cats, subcats, vi)).to_string(),
        render_svg(marimekko(cats, subcats, vf)).to_string(),
    )


def test_radar_accepts_nested_list_int_matching_list_float64() raises:
    var indicators: List[String] = ["A", "B", "C"]
    var max_values: List[Float64] = [100.0, 100.0, 100.0]
    var names: List[String] = ["S1", "S2"]
    var vi: List[List[Int]] = [[90, 60, 80], [65, 85, 55]]
    var vf: List[List[Float64]] = [[90.0, 60.0, 80.0], [65.0, 85.0, 55.0]]
    assert_equal(
        render_svg(radar(indicators, max_values, names, vi)).to_string(),
        render_svg(radar(indicators, max_values, names, vf)).to_string(),
    )


def test_radar_accepts_list_int_max_values_matching_list_float64() raises:
    # radar()'s other DType-generic axis (#173) -- max_values, a flat
    # List[Float64], is independent of series_values' own nested axis
    # tested above; each overload here generalizes exactly one of the
    # two, never both together (see encode_radar()'s own docstring).
    var indicators: List[String] = ["A", "B", "C"]
    var names: List[String] = ["S1", "S2"]
    var series_values: List[List[Float64]] = [[90.0, 60.0, 80.0], [65.0, 85.0, 55.0]]
    var max_i: List[Int] = [100, 100, 100]
    var max_f: List[Float64] = [100.0, 100.0, 100.0]
    assert_equal(
        render_svg(radar(indicators, max_i, names, series_values)).to_string(),
        render_svg(radar(indicators, max_f, names, series_values)).to_string(),
    )


def test_parallel_accepts_nested_list_int_matching_list_float64() raises:
    var dims: List[String] = ["A", "B"]
    var rows: List[String] = ["R1", "R2"]
    var vi: List[List[Int]] = [[180, 32], [280, 22]]
    var vf: List[List[Float64]] = [[180.0, 32.0], [280.0, 22.0]]
    assert_equal(
        render_svg(parallel(vi, dims, rows)).to_string(), render_svg(parallel(vf, dims, rows)).to_string()
    )


def test_polar_series_accepts_nested_list_int_matching_list_float64() raises:
    var angle: List[Float64] = [0.0, 1.0]
    var names: List[String] = ["A", "B"]
    var vi: List[List[Int]] = [[68, 69], [57, 61]]
    var vf: List[List[Float64]] = [[68.0, 69.0], [57.0, 61.0]]
    assert_equal(
        render_svg(polar_series(angle, names, vi)).to_string(),
        render_svg(polar_series(angle, names, vf)).to_string(),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
