"""Shared helpers for the tests/test_*.mojo files split out of what used
to be one big test_plot.mojo -- kept in its module (not a *.mojo
file with its main()) so every split-out test file can import
these instead of redefining them; deliberately not a real dataviz_mojo
sub-package (tests/ itself stays a plain sibling directory of the
importable package, not one -- see dataviz_mojo/__init__.mojo's docstring/pixi.toml's package-declaration comment for why tests/
examples can never become a package themselves, since every file in
here has its main() and Mojo refuses to `mojo package`/`mojo
precompile` a package directory containing one). Callers need an extra
`-I tests` alongside the usual `-I .` to resolve `from _test_helpers
import ...` -- see pixi.toml's test task.
"""

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from std.testing import assert_equal

from dataviz_mojo.colors import WHITE

comptime BG = WHITE


def _count_color(c: Canvas, color: Color) -> Int:
    var count = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == color.r and p.g == color.g and p.b == color.b:
                count += 1
    return count


def _assert_color(c: Canvas, x: Int, y: Int, expected: Color, label: String) raises:
    var p = c.get_pixel(x, y)
    assert_equal(p.r, expected.r, label)
    assert_equal(p.g, expected.g, label)
    assert_equal(p.b, expected.b, label)
