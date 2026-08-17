"""Tests for ordinal_scale.mojo: OrdinalScale's band math, hand-
computed independently before trusting the Mojo implementation.
"""

from std.testing import assert_equal, TestSuite

from dataviz_mojo.ordinal_scale import OrdinalScale


def test_band_positions_match_hand_computed_values() raises:
    # domain of 3 categories, range [0, 300] (a clean multiple of 3),
    # padding 0.2 -- step = 100, bandwidth = 80 (100 * 0.8), each
    # band's left edge 10px in from its own slot start (100 * 0.2/2).
    var domain: List[String] = ["a", "b", "c"]
    var s = OrdinalScale(domain^, 0.0, 300.0, padding=0.2)

    assert_equal(s.step(), 100.0)
    assert_equal(s.bandwidth(), 80.0)

    assert_equal(s.band_start(0), 10.0)
    assert_equal(s.center(0), 50.0)

    assert_equal(s.band_start(1), 110.0)
    assert_equal(s.center(1), 150.0)

    assert_equal(s.band_start(2), 210.0)
    assert_equal(s.center(2), 250.0)


def test_empty_domain_does_not_divide_by_zero() raises:
    var domain = List[String]()
    var s = OrdinalScale(domain^, 0.0, 300.0)
    assert_equal(s.step(), 0.0)
    assert_equal(s.bandwidth(), 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
