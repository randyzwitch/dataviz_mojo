"""Tests for color_scale.mojo: ColorScale.color_at -- shares its
interpolation math with canvas_mojo.gradient's LinearGradient/
RadialGradient (already exhaustively tested there), so these focus on
what's specific to ColorScale: projecting a data domain (not a pixel
position) onto [0, 1], and the zero-span-domain degenerate case.
Expected values independently computed by hand before trusting the
Mojo implementation (same white-on-black-gives-the-coverage-fraction-
directly technique canvas_mojo/tests/test_gradient.mojo's tests use).
"""

from std.testing import assert_equal, TestSuite

from dataviz_mojo.color_scale import ColorScale
from dataviz_mojo.colors import BLACK, BLUE, RED, WHITE


def test_color_scale_matches_hand_computed_values() raises:
    var s = ColorScale(0.0, 10.0)
    s.add_stop(0.0, BLACK)
    s.add_stop(1.0, WHITE)

    var lo = s.color_at(0.0)
    assert_equal(lo.r, 0)
    assert_equal(lo.g, 0)
    assert_equal(lo.b, 0)

    var hi = s.color_at(10.0)
    assert_equal(hi.r, 255)
    assert_equal(hi.g, 255)
    assert_equal(hi.b, 255)

    var mid = s.color_at(5.0)
    assert_equal(mid.r, 128)
    assert_equal(mid.g, 128)
    assert_equal(mid.b, 128)


def test_color_scale_clamps_beyond_the_domain() raises:
    var s = ColorScale(0.0, 10.0)
    s.add_stop(0.0, BLACK)
    s.add_stop(1.0, WHITE)

    var below = s.color_at(-50.0)
    assert_equal(below.r, 0)
    assert_equal(below.g, 0)
    assert_equal(below.b, 0)

    var above = s.color_at(500.0)
    assert_equal(above.r, 255)
    assert_equal(above.g, 255)
    assert_equal(above.b, 255)


def test_color_scale_zero_span_domain_returns_the_lowest_offset_stop() raises:
    # A constant-valued color column -- span is 0, so t is always 0.0
    # regardless of the actual data value, landing on the lowest-
    # offset stop's color (blue here), not a crash from dividing by
    # the zero span.
    var s = ColorScale(5.0, 5.0)
    s.add_stop(0.0, BLUE)
    s.add_stop(1.0, RED)

    var a = s.color_at(5.0)
    var b = s.color_at(999.0)
    assert_equal(a.r, 0)
    assert_equal(a.b, 255)
    assert_equal(b.r, 0)
    assert_equal(b.b, 255)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
