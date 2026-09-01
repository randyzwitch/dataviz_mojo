"""Shared helpers for the tests/test_*.mojo files -- kept in its
module (not a *.mojo file with its main()) so every test file can
import these instead of redefining them; not a real dataviz
sub-package (tests/ itself stays a plain sibling directory of the
importable package, not one, since every file in here has a main()
and Mojo refuses to `mojo package`/`mojo precompile` a package
directory containing one). Callers need an extra `-I tests` alongside
the usual `-I .` to resolve `from _test_helpers import .` -- see
pixi.toml's test task.
"""

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from std.testing import assert_equal, assert_true

from dataviz.colors import WHITE

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


def _assert_near_color(c: Canvas, x: Int, y: Int, expected: Color, tolerance: Int, label: String) raises:
    """`_assert_color()`'s tolerant sibling, for a *stroked* position
    (an axis line, a gridline, an annotation line -- anything whose
    footprint is only 1-2px wide) rather than a filled mark's solid
    interior. `render()`'s supersample-then-downsample (`_RASTER_
    SUPERSAMPLE`, plot.mojo) genuinely has no single output pixel that
    lands fully opaque for a stroke that thin -- the stroke's true
    (supersampled) footprint straddles a downsample block boundary
    unevenly almost regardless of position, so averaging never fully
    saturates any one output pixel the way it would for a filled
    shape's own interior (see `_RASTER_SUPERSAMPLE`'s own docstring for
    why a *filled* region's interior doesn't have this problem: every
    subpixel already agrees, so nothing there ever blends). `_assert_
    color()` remains the right choice for anything with real interior
    area to sample away from its own edge."""
    var p = c.get_pixel(x, y)
    assert_true(
        abs(Int(p.r) - Int(expected.r)) <= tolerance
        and abs(Int(p.g) - Int(expected.g)) <= tolerance
        and abs(Int(p.b) - Int(expected.b)) <= tolerance,
        label + " (got (" + String(p.r) + "," + String(p.g) + "," + String(p.b) + "), expected within "
        + String(tolerance) + " of (" + String(expected.r) + "," + String(expected.g) + "," + String(expected.b) + "))",
    )
