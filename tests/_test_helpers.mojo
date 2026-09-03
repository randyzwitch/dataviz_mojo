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

from canvas.color import Color
from canvas.buffer import Canvas
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


def _unique_categories(data: List[String]) -> List[String]:
    """Every distinct value in `data`, in first-seen order, by a plain
    O(n^2) scan.

    A deliberately naive reference implementation, kept here rather
    than in the package: `dataviz.plot._categorical_indices` and
    `dataviz.edges._edge_node_index` resolve the same domain in one
    hashed pass, and the tests that check them assert agreement against
    this. Both of these used to live in plot.mojo and be called by the
    render paths, until those two replaced them; keeping the obvious
    version around as an oracle is worth more than deleting it, but it
    has no business shipping inside the package.
    """
    var result = List[String]()
    for v in data:
        var found = False
        for existing in result:
            if existing == v:
                found = True
                break
        if not found:
            result.append(v)
    return result^


def _index_of(data: List[String], value: String) -> Int:
    """`value`'s position in `data`, or -1 -- the linear search half of
    the oracle described in `_unique_categories` above."""
    for i in range(len(data)):
        if data[i] == value:
            return i
    return -1
