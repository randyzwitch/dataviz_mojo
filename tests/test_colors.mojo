"""Tests for colors.mojo -- spot checks against the actual CSS Color
Module Level 3 spec (<https://www.w3.org/TR/css-color-3/#svg-color>),
not just re-reading colors.mojo's values back at itself: the three
additive primaries, a representative multi-word name, that both
spellings CSS itself standardizes for six names resolve to the
identical color, and that a named constant works exactly like any
other `Color` literal through a real render (see the "why comptime,
not a lookup" paragraph in colors.mojo's docstring -- this is what
that buys: no separate integration path to test, just Theme.mark_color
fed a different value).
"""

from std.testing import assert_equal, TestSuite

from canvas_mojo.color import Color
from dataviz_mojo import (
    render,
    RED,
    GREEN,
    BLUE,
    BLACK,
    WHITE,
    CORNFLOWERBLUE,
    GRAY,
    GREY,
    DARKGRAY,
    DARKGREY,
    DIMGRAY,
    DIMGREY,
    LIGHTGRAY,
    LIGHTGREY,
    LIGHTSLATEGRAY,
    LIGHTSLATEGREY,
    SLATEGRAY,
    SLATEGREY,
    Theme,
    bar,
)

from _test_helpers import _count_color


def _assert_rgb(c: Color, r: Int, g: Int, b: Int, label: String) raises:
    assert_equal(Int(c.r), r, label + ": r")
    assert_equal(Int(c.g), g, label + ": g")
    assert_equal(Int(c.b), b, label + ": b")
    assert_equal(Int(c.a), 255, label + ": a defaults fully opaque")


def test_primary_colors_match_the_css_spec() raises:
    _assert_rgb(RED, 255, 0, 0, "RED")
    _assert_rgb(GREEN, 0, 128, 0, "GREEN")  # CSS "green", not the brighter "lime" (0,255,0)
    _assert_rgb(BLUE, 0, 0, 255, "BLUE")
    _assert_rgb(BLACK, 0, 0, 0, "BLACK")
    _assert_rgb(WHITE, 255, 255, 255, "WHITE")


def test_multiword_name_matches_the_css_spec() raises:
    _assert_rgb(CORNFLOWERBLUE, 100, 149, 237, "CORNFLOWERBLUE")


def test_gray_grey_spelling_pairs_are_identical_colors() raises:
    # CSS standardizes both spellings for these six names -- picking
    # one and dropping the other would just be a different, equally
    # arbitrary standard (see colors.mojo's docstring), so both
    # are provided, and must actually agree with each other.
    _assert_rgb(GREY, Int(GRAY.r), Int(GRAY.g), Int(GRAY.b), "GREY matches GRAY")
    _assert_rgb(DARKGREY, Int(DARKGRAY.r), Int(DARKGRAY.g), Int(DARKGRAY.b), "DARKGREY matches DARKGRAY")
    _assert_rgb(DIMGREY, Int(DIMGRAY.r), Int(DIMGRAY.g), Int(DIMGRAY.b), "DIMGREY matches DIMGRAY")
    _assert_rgb(LIGHTGREY, Int(LIGHTGRAY.r), Int(LIGHTGRAY.g), Int(LIGHTGRAY.b), "LIGHTGREY matches LIGHTGRAY")
    _assert_rgb(
        LIGHTSLATEGREY,
        Int(LIGHTSLATEGRAY.r),
        Int(LIGHTSLATEGRAY.g),
        Int(LIGHTSLATEGRAY.b),
        "LIGHTSLATEGREY matches LIGHTSLATEGRAY",
    )
    _assert_rgb(SLATEGREY, Int(SLATEGRAY.r), Int(SLATEGRAY.g), Int(SLATEGRAY.b), "SLATEGREY matches SLATEGRAY")


def test_named_color_works_as_a_theme_mark_color_through_a_real_render() raises:
    # A real render, not just reading the constant back -- confirms a
    # named color reaches the renderer exactly like any other Color
    # literal, with no separate integration path (see
    # colors.mojo's "why comptime, not a lookup" paragraph). A
    # plain non-zero count, not a specific hand-derived pixel -- bar()
    # layout itself is already exhaustively covered in test_bar.mojo;
    # all this needs to prove is that the fill color a caller asked
    # for is the fill color that actually landed on the canvas.
    var cats: List[String] = ["a", "b"]
    var values: List[Float64] = [3.0, 5.0]
    var c = render(bar(cats, values, theme=Theme(mark_color=CORNFLOWERBLUE)))

    assert_equal(_count_color(c, CORNFLOWERBLUE) > 0, True, "bar filled with a named color renders that exact color")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
