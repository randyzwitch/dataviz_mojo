"""`dataviz.core.stats` and `dataviz.core.cluster`: the estimation shared
by marks that draw an estimate with its uncertainty (#350, #352), and
the hierarchical clustering a clustermap's reordering comes from (#355).
Every value here is worked out by hand and pinned, away from any
rendering.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from dataviz.core.cluster import (
    DistanceMetric,
    Linkage,
    linkage,
)
from dataviz.core.stats import (
    ErrorBar,
    Estimator,
    _aggregate,
    _aggregate_by_x,
    _estimate,
    _interval,
    _ols_fit,
    _sample_sd,
    _t_quantile,
)


def test_ols_fit_matches_hand_derived_line_and_residual_error() raises:
    # x=[1..5], y=[1,3,2,5,4]: slope 0.8, intercept 0.6 (the values
    # annotate_best_fit has always drawn). Residuals -0.4/0.8/-1/1.2/-0.6
    # give SS_res 3.6 over n-2 = 3 -> s = sqrt(1.2). Sxx = 55 - 5*9 = 10.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var f = _ols_fit(x, y)
    assert_equal(f.n, 5)
    assert_almost_equal(f.slope, 0.8, atol=1e-12)
    assert_almost_equal(f.intercept, 0.6, atol=1e-12)
    assert_almost_equal(f.mean_x, 3.0, atol=1e-12)
    assert_almost_equal(f.sxx, 10.0, atol=1e-12)
    assert_almost_equal(f.residual_se, 1.0954451150103321, atol=1e-12)


def test_band_half_width_is_narrowest_at_mean_x_and_flares() raises:
    # Same fit; t(0.95, df=3) = 3.182.
    # at x = mean_x = 3: 3.182 * sqrt(1.2) * sqrt(1/5)       = 1.5588552
    # at x = 1:          3.182 * sqrt(1.2) * sqrt(1/5 + 4/10) = 2.7000164
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var f = _ols_fit(x, y)
    var at_mean = f.band_half_width(3.0, 0.95)
    var at_end = f.band_half_width(1.0, 0.95)
    assert_almost_equal(at_mean, 1.5588552, atol=1e-6)
    assert_almost_equal(at_end, 2.7000164, atol=1e-6)
    assert_almost_equal(f.band_half_width(5.0, 0.95), at_end, atol=1e-12)


def test_perfect_fit_has_zero_residual_error_and_zero_width_band() raises:
    # y = 2x exactly: slope 2, intercept 0, every residual 0, so the
    # band collapses onto the line -- the degenerate case #352 names.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.0, 4.0, 6.0, 8.0, 10.0]
    var f = _ols_fit(x, y)
    assert_equal(f.slope, 2.0)
    assert_equal(f.intercept, 0.0)
    assert_equal(f.residual_se, 0.0)
    assert_equal(f.band_half_width(1.0, 0.95), 0.0)


def test_t_quantile_table_and_normal_tail() raises:
    assert_equal(_t_quantile(0.95, 1), 12.706)
    assert_equal(_t_quantile(0.95, 3), 3.182)
    assert_equal(_t_quantile(0.90, 10), 1.812)
    assert_equal(_t_quantile(0.99, 30), 2.750)
    assert_equal(_t_quantile(0.95, 31), 1.960)
    assert_equal(_t_quantile(0.95, 1000), 1.960)


def test_stats_raise_where_the_estimate_is_undefined() raises:
    var x2: List[Float64] = [1.0, 2.0]
    var y2: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = _ols_fit(x2, y2).band_half_width(1.5, 0.95)
    var xv: List[Float64] = [3.0, 3.0, 3.0]
    var yv: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises():
        _ = _ols_fit(xv, yv)
    with assert_raises():
        _ = _t_quantile(0.8, 5)
    with assert_raises():
        _ = _t_quantile(0.95, 0)


def _eight() -> List[Float64]:
    # The classic sd example: mean 5, sum of squared deviations 32.
    var v: List[Float64] = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
    return v^


def test_estimators_match_hand_derived_values() raises:
    var v = _eight()
    assert_equal(_estimate(v, Estimator.MEAN), 5.0)
    assert_equal(_estimate(v, Estimator.MEDIAN), 4.5)
    assert_equal(_estimate(v, Estimator.COUNT), 8.0)
    assert_equal(_estimate(v, Estimator.SUM), 40.0)
    var unsorted: List[Float64] = [9.0, 2.0, 5.0]
    assert_equal(_estimate(unsorted, Estimator.MEDIAN), 5.0)


def test_sd_and_se_intervals_are_symmetric_and_hand_derived() raises:
    # sample sd = sqrt(32 / 7) = 2.1380899; se = sd / sqrt(8) = 0.7559289.
    var v = _eight()
    assert_almost_equal(_sample_sd(v), 2.1380899352993950, atol=1e-12)
    var sd = _interval(v, Estimator.MEAN, ErrorBar.sd(), 1)
    assert_almost_equal(sd[0], 5.0 - 2.1380899352993950, atol=1e-12)
    assert_almost_equal(sd[1], 5.0 + 2.1380899352993950, atol=1e-12)
    var se2 = _interval(v, Estimator.MEAN, ErrorBar.se(2.0), 1)
    assert_almost_equal(se2[0], 5.0 - 2.0 * 0.7559289460184544, atol=1e-12)
    assert_almost_equal(se2[1], 5.0 + 2.0 * 0.7559289460184544, atol=1e-12)


def test_percentile_interval_follows_numpy_linear_interpolation() raises:
    # 50% PI of the eight: numpy's 25th percentile is 4.0 (rank 1.75
    # between two 4s) and 75th is 5.5 (rank 5.25 between 5 and 7).
    var v = _eight()
    var pi = _interval(v, Estimator.MEAN, ErrorBar.pi(0.5), 1)
    assert_equal(pi[0], 4.0)
    assert_equal(pi[1], 5.5)


def test_count_and_none_have_an_empty_interval() raises:
    var v = _eight()
    var c = _interval(v, Estimator.COUNT, ErrorBar.ci(), 1)
    assert_equal(c[0], 8.0)
    assert_equal(c[1], 8.0)
    var n = _interval(v, Estimator.MEAN, ErrorBar.none(), 1)
    assert_equal(n[0], 5.0)
    assert_equal(n[1], 5.0)


def test_bootstrap_ci_is_seeded_contains_the_estimate_and_widens_with_spread() raises:
    var v = _eight()
    var a = _interval(v, Estimator.MEAN, ErrorBar.ci(0.95), 12345)
    var b = _interval(v, Estimator.MEAN, ErrorBar.ci(0.95), 12345)
    assert_equal(a[0], b[0], "the same seed gives the same interval")
    assert_equal(a[1], b[1])
    assert_true(a[0] <= 5.0 and 5.0 <= a[1], "the interval brackets the mean")
    assert_true(a[0] < a[1], "and is not empty")
    var wide = List[Float64]()
    for x in v:
        wide.append(5.0 + 3.0 * (x - 5.0))
    var w = _interval(wide, Estimator.MEAN, ErrorBar.ci(0.95), 12345)
    assert_true(
        (w[1] - w[0]) > (a[1] - a[0]), "a wider sample gives a wider interval"
    )


def test_bootstrap_ci_is_pinned_for_the_default_seed() raises:
    # Read once and pinned, so a change to the generator, the resample
    # count or the percentile rule shows up here rather than as a silent
    # shift in every chart's whiskers. 1000 resamples of the eight, seed
    # 12345, 95% percentile interval of the resampled means.
    var v = _eight()
    var iv = _interval(v, Estimator.MEAN, ErrorBar.ci(0.95), 12345)
    assert_almost_equal(iv[0], 3.75, atol=1e-9)
    assert_almost_equal(iv[1], 6.625, atol=1e-9)


def test_aggregate_groups_in_first_seen_order() raises:
    var groups: List[String] = ["b", "a", "b", "a", "c"]
    var values: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var agg = _aggregate(groups, values, Estimator.MEAN, ErrorBar.none(), 1)
    assert_equal(len(agg.categories), 3)
    assert_equal(agg.categories[0], "b")
    assert_equal(agg.categories[1], "a")
    assert_equal(agg.categories[2], "c")
    assert_equal(agg.estimates[0], 2.0)
    assert_equal(agg.estimates[1], 3.0)
    assert_equal(agg.estimates[2], 5.0)


def test_aggregate_by_x_groups_exact_keys_and_sorts_them() raises:
    # Repeated measurements at x=2, 1 and 3, given out of order; groups
    # come back sorted by x with each group's mean.
    var x: List[Float64] = [2.0, 1.0, 2.0, 3.0, 1.0, 3.0]
    var y: List[Float64] = [20.0, 10.0, 22.0, 30.0, 12.0, 34.0]
    var agg = _aggregate_by_x(x, y, Estimator.MEAN, ErrorBar.se(), 1)
    assert_equal(len(agg.xs), 3)
    assert_equal(agg.xs[0], 1.0)
    assert_equal(agg.xs[1], 2.0)
    assert_equal(agg.xs[2], 3.0)
    assert_equal(agg.estimates[0], 11.0)
    assert_equal(agg.estimates[1], 21.0)
    assert_equal(agg.estimates[2], 32.0)
    # se of a pair {a, b} is |a - b| / 2: 1.0, 1.0, 2.0.
    assert_almost_equal(agg.lows[0], 10.0, atol=1e-12)
    assert_almost_equal(agg.highs[2], 34.0, atol=1e-12)
    # Nearly equal x values are distinct positions, not one group.
    var xn: List[Float64] = [1.0, 1.0000001]
    var yn: List[Float64] = [5.0, 7.0]
    assert_equal(
        len(_aggregate_by_x(xn, yn, Estimator.MEAN, ErrorBar.none(), 1).xs), 2
    )


def test_estimation_raises_on_bad_input() raises:
    var empty = List[Float64]()
    with assert_raises():
        _ = _estimate(empty, Estimator.MEAN)
    var v = _eight()
    with assert_raises():
        _ = _interval(v, Estimator.MEAN, ErrorBar.ci(1.5), 1)
    var g: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0]
    with assert_raises():
        _ = _aggregate(g, one, Estimator.MEAN, ErrorBar.none(), 1)


# ==== hierarchical clustering (#355) ====
# The numbers a clustermap's reordering comes from, checked without
# drawing anything. The four-point example below is worked by hand in
# the comment, which is what makes it a test of the algorithm rather
# than a recording of its output.


def _four_points() -> List[List[Float64]]:
    """Four points on a line at 0, 1, 4 and 6.

    Pairwise distances, by hand: (0,1)=1, (0,2)=4, (0,3)=6, (1,2)=3,
    (1,3)=5, (2,3)=2.
    """
    var out = List[List[Float64]]()
    var at: List[Float64] = [0.0, 1.0, 4.0, 6.0]
    for v in at:
        var row = List[Float64]()
        row.append(v)
        out.append(row^)
    return out^


def test_average_linkage_matches_the_hand_worked_example() raises:
    # Closest pair is (0,1) at 1. Merging them puts the new cluster at
    # (4+3)/2 = 3.5 from point 2 and (6+5)/2 = 5.5 from point 3. The
    # closest pair is now (2,3) at 2. Merging those leaves one distance,
    # (3.5 + 5.5)/2 = 4.5.
    var tree = linkage(
        _four_points(), DistanceMetric.EUCLIDEAN, Linkage.AVERAGE
    )
    assert_equal(len(tree.merges), 3, "three merges for four points")
    assert_equal(tree.merges[0].left, 0)
    assert_equal(tree.merges[0].right, 1)
    assert_equal(tree.merges[0].height, 1.0)
    assert_equal(tree.merges[0].size, 2)
    assert_equal(tree.merges[1].left, 2)
    assert_equal(tree.merges[1].right, 3)
    assert_equal(tree.merges[1].height, 2.0)
    assert_equal(tree.merges[2].left, 4, "the root joins the two pairs")
    assert_equal(tree.merges[2].right, 5)
    assert_equal(tree.merges[2].height, 4.5)
    assert_equal(tree.merges[2].size, 4)


def test_single_and_complete_differ_where_the_hand_work_says() raises:
    # Same two pairs, and only the last height changes: single takes the
    # closest pair across the two clusters (3), complete the furthest
    # (6). That the first two merges are identical is the point -- the
    # linkage rule only starts to matter once there are clusters.
    var single = linkage(
        _four_points(), DistanceMetric.EUCLIDEAN, Linkage.SINGLE
    )
    var complete = linkage(
        _four_points(), DistanceMetric.EUCLIDEAN, Linkage.COMPLETE
    )
    assert_equal(single.merges[0].height, 1.0)
    assert_equal(complete.merges[0].height, 1.0)
    assert_equal(single.merges[1].height, 2.0)
    assert_equal(complete.merges[1].height, 2.0)
    assert_equal(single.merges[2].height, 3.0, "closest across the pairs")
    assert_equal(complete.merges[2].height, 6.0, "furthest across them")


def test_the_leaf_order_is_a_permutation_in_tree_order() raises:
    var tree = linkage(_four_points())
    assert_equal(len(tree.leaf_order), 4)
    var seen = List[Bool]()
    for _ in range(4):
        seen.append(False)
    for v in tree.leaf_order:
        assert_true(v >= 0 and v < 4, "a real row index")
        assert_true(not seen[v], "each row exactly once")
        seen[v] = True
    assert_equal(tree.leaf_order[0], 0, "and in the tree's own order")
    assert_equal(tree.leaf_order[1], 1)
    assert_equal(tree.leaf_order[2], 2)
    assert_equal(tree.leaf_order[3], 3)


def test_a_child_always_comes_before_its_parent() raises:
    # What sorting the merges by height buys: anything reading the tree
    # can place every node in one forward pass.
    var tree = linkage(_four_points())
    var n = 4
    for k in range(len(tree.merges)):
        var m = tree.merges[k]
        assert_true(m.left < n + k, "left child already exists")
        assert_true(m.right < n + k, "right child already exists")
        if k > 0:
            assert_true(
                tree.merges[k].height >= tree.merges[k - 1].height,
                "heights do not go backwards",
            )


def _blocks() -> List[List[Float64]]:
    """Six rows in two obvious blocks, interleaved so the input order
    cannot be mistaken for the answer: rows 0, 2, 4 are one shape and
    rows 1, 3, 5 the other.
    """
    var out = List[List[Float64]]()
    for i in range(6):
        var row = List[Float64]()
        for c in range(4):
            if i % 2 == 0:
                row.append(10.0 + Float64(c) + Float64(i) * 0.01)
            else:
                row.append(90.0 - Float64(c) + Float64(i) * 0.01)
        out.append(row^)
    return out^


def test_block_structure_comes_out_grouped() raises:
    # A property rather than a pinned order, so it survives any
    # tie-breaking change: whatever the leaf order is, each block's rows
    # are contiguous in it. That is the whole claim a clustermap makes.
    var tree = linkage(_blocks())
    ref order = tree.leaf_order
    var first_parity = order[0] % 2
    var switches = 0
    for i in range(1, len(order)):
        if order[i] % 2 != order[i - 1] % 2:
            switches += 1
    assert_equal(
        switches, 1, "the order crosses between the blocks exactly once"
    )
    assert_true(first_parity == 0 or first_parity == 1)


def test_correlation_groups_rows_that_move_together() raises:
    # Two rows with the same shape at very different levels are far
    # apart by Euclidean distance and close by correlation. This is the
    # reason the metric is a choice rather than a constant.
    var rows = List[List[Float64]]()
    var low: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var high: List[Float64] = [101.0, 102.0, 103.0, 104.0]
    var falling: List[Float64] = [4.0, 3.0, 2.0, 1.0]
    rows.append(low^)
    rows.append(high^)
    rows.append(falling^)
    var by_shape = linkage(rows, DistanceMetric.CORRELATION, Linkage.AVERAGE)
    # The two rising rows are identical in shape, so they join at a
    # distance of zero, before anything joins the falling one.
    assert_true(
        by_shape.merges[0].height < 1e-9,
        "two identically shaped rows are the same to correlation",
    )
    assert_true(
        by_shape.merges[1].height > 1.0,
        "and the falling row is far from both",
    )


def test_ward_needs_euclidean_distance() raises:
    with assert_raises(contains="only means anything with"):
        _ = linkage(_four_points(), DistanceMetric.CORRELATION, Linkage.WARD)


def test_clustering_checks_its_input() raises:
    var one = List[List[Float64]]()
    var row: List[Float64] = [1.0]
    one.append(row^)
    with assert_raises(contains="at least two rows"):
        _ = linkage(one)

    var ragged = List[List[Float64]]()
    var a: List[Float64] = [1.0, 2.0]
    var b: List[Float64] = [1.0]
    ragged.append(a^)
    ragged.append(b^)
    with assert_raises(contains="same number of columns"):
        _ = linkage(ragged)

    var bad = List[List[Float64]]()
    var c: List[Float64] = [1.0, 2.0]
    var d: List[Float64] = [1.0, Float64("nan")]
    bad.append(c^)
    bad.append(d^)
    with assert_raises(contains="must be finite"):
        _ = linkage(bad)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
