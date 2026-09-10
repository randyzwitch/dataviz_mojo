"""`_snap_pixel_edge` breaks its tie by rule, not by float error.

A pixel `k` spans `k - 0.5` to `k + 0.5`, so the snap targets are the
half-integers and a coordinate exactly on a whole number -- a pixel
center -- is equidistant from two of them. That is where data lands all
the time (a symmetric domain's midpoint, a band center), and a
`LinearScale`'s `intercept + slope * v` can come out one ULP under the
exact whole number. Without a tolerance that ULP moved the edge a whole
pixel (#314); with it, the coordinate the rule sees is the one the
arithmetic meant.
"""

from std.testing import TestSuite, assert_equal

from dataviz.pixel_snap import _snap_pixel_center, _snap_pixel_edge


def test_snap_edge_lands_on_half_integers() raises:
    assert_equal(_snap_pixel_edge(134.4), 134.5)
    assert_equal(_snap_pixel_edge(134.6), 134.5)
    assert_equal(_snap_pixel_edge(135.9), 135.5)
    assert_equal(_snap_pixel_edge(136.1), 136.5)
    assert_equal(_snap_pixel_edge(135.5), 135.5)
    assert_equal(_snap_pixel_edge(0.0), 0.5)


def test_snap_edge_tie_goes_up_and_float_error_does_not_change_it() raises:
    # The case from #314: domain [9.5, 20.5], range [250, 20],
    # to_pixel(15.0) is mathematically 135.0 and comes out
    # 134.99999999999997. Both must snap to the same boundary.
    assert_equal(_snap_pixel_edge(135.0), 135.5)
    assert_equal(_snap_pixel_edge(134.99999999999997), 135.5)


def test_snap_edge_tolerance_is_far_below_any_real_fraction() raises:
    # A tenth of a pixel under the center is a real position, not float
    # noise, and snaps down as it always did.
    assert_equal(_snap_pixel_edge(134.9), 134.5)
    assert_equal(_snap_pixel_edge(134.999), 134.5)


def test_snap_center_is_unchanged() raises:
    assert_equal(_snap_pixel_center(134.4), 134.0)
    assert_equal(_snap_pixel_center(134.6), 135.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
