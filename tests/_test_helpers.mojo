"""Shared helpers for tests/test_*.mojo, kept in a module without a
`main()` so every test file can import them. Not a dataviz
sub-package: tests/ contains files with `main()`, which `mojo
package` refuses. Callers pass `-I tests` alongside `-I .` (see
pixi.toml's test task).
"""

from canvas.color import Color
from canvas.buffer import Canvas
from std.testing import assert_equal, assert_true

from dataviz.colors import WHITE

comptime BG = WHITE


struct Lcg(Movable):
    """A tiny linear congruential generator, for the property-style
    sweeps (#220). Its own generator rather than a dependency, and
    deterministic rather than seeded from the clock: a sweep that fails
    has to fail again on the next run, and the failing case has to be
    reproducible from the seed alone so it can be lifted into a fixed
    regression test.

    Knuth's MMIX constants. The low bits of an LCG are famously poor,
    so every draw is taken from the high 32 bits.
    """

    var _state: UInt64

    def __init__(out self, seed: UInt64 = 1):
        """Construct a generator.

        Args:
            seed: Starting state; any value gives a distinct stream.
        """
        self._state = seed

    def next_bits(mut self) -> UInt64:
        """The next 32-bit draw, taken from the state's high bits.

        Returns:
            A value in [0, 2^32).
        """
        self._state = self._state * 6364136223846793005 + 1442695040888963407
        return self._state >> 32

    def unit(mut self) -> Float64:
        """The next draw as a fraction.

        Returns:
            A value in [0, 1).
        """
        return Float64(self.next_bits()) / 4294967296.0

    def uniform(mut self, lo: Float64, hi: Float64) -> Float64:
        """The next draw scaled to a range.

        Args:
            lo: Lower bound, inclusive.
            hi: Upper bound, exclusive.

        Returns:
            A value in [lo, hi).
        """
        return lo + self.unit() * (hi - lo)

    def below(mut self, n: Int) -> Int:
        """The next draw as an index.

        Args:
            n: Exclusive upper bound; must be positive.

        Returns:
            A value in [0, n).
        """
        return Int(self.next_bits() % UInt64(n))


# ---------------------------------------------------------------
# Structural SVG helpers (#219)
#
# SVG tests assert on `to_string()` substrings, which catches gross
# breakage but not structure: a mark emitting its rects outside the
# annotated tooltip group, an unclosed `<g>`, or a legend drawing the
# right colours the wrong number of times all pass a substring check.
#
# canvas_mojo's SVG is its own output, one element per line with a
# fixed attribute order, so a line-oriented scan is enough and no XML
# parser is needed. These stay deliberately dumb for that reason: they
# read what canvas actually emits, not what SVG permits in general.
# ---------------------------------------------------------------


def _count_tag(svg: String, tag: String) -> Int:
    """How many `<tag ` elements the document contains.

    Args:
        svg: The rendered document.
        tag: Element name, without angle brackets (`"rect"`, `"path"`).

    Returns:
        The number of occurrences.
    """
    return svg.count("<" + tag + " ") + svg.count("<" + tag + ">")


def _attr_values(svg: String, tag: String, attr: String) -> List[String]:
    """Every value of `attr` on every `<tag>` element, in document order.

    Reads only elements of that tag, so `fill` on `<rect>` doesn't pick
    up `fill` on `<text>` -- telling those apart is most of the point of
    asserting structurally rather than on substrings.

    Args:
        svg: The rendered document.
        tag: Element name, without angle brackets.
        attr: Attribute name, without the `=`.

    Returns:
        The values, one per element that carries the attribute.
    """
    var out = List[String]()
    var needle = "<" + tag + " "
    var key = " " + attr + '="'
    var rest = svg
    while True:
        var at = rest.find(needle)
        if at < 0:
            break
        var after = String(rest[byte = at + needle.byte_length() :])
        var end = after.find(">")
        if end < 0:
            break
        var element = String(after[byte=0:end])
        var k = element.find(key)
        if k >= 0:
            var vstart = k + key.byte_length()
            var vend = element.find('"', vstart)
            if vend > vstart:
                out.append(String(element[byte=vstart:vend]))
        rest = after
    return out^


def _group_titles(svg: String) -> List[String]:
    """The `<title>` text of every annotated group, in document order --
    what `Theme.svg_tooltips` produces, and what a browser shows on
    hover.

    Args:
        svg: The rendered document.

    Returns:
        One entry per `<title>`, still XML-escaped as canvas wrote it.
    """
    var out = List[String]()
    var rest = svg
    while True:
        var at = rest.find("<title>")
        if at < 0:
            break
        var after = String(rest[byte = at + 7 :])
        var end = after.find("</title>")
        if end < 0:
            break
        out.append(String(after[byte=0:end]))
        rest = String(after[byte = end + 8 :])
    return out^


def _assert_well_formed_svg(svg: String, label: String) raises:
    """The document opens and closes, and every `<g>` is closed.

    Not a schema check -- just the two ways canvas's own emitters can go
    wrong: an element opened and never closed (`begin_annotated_group`
    without its `end_`), or a truncated document.

    Args:
        svg: The rendered document.
        label: Included in any failure message.

    Raises:
        Error: The document is unbalanced or truncated.
    """
    assert_true(svg.startswith("<svg"), "does not open with <svg: " + label)
    assert_true(
        svg.strip().endswith("</svg>"), "does not end with </svg>: " + label
    )
    var opens = svg.count("<g>") + svg.count("<g ")
    var closes = svg.count("</g>")
    assert_equal(opens, closes, "unbalanced <g> in " + label)


def _count_color(c: Canvas, color: Color) -> Int:
    var count = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == color.r and p.g == color.g and p.b == color.b:
                count += 1
    return count


def _assert_color(
    c: Canvas, x: Int, y: Int, expected: Color, label: String
) raises:
    var p = c.get_pixel(x, y)
    assert_equal(p.r, expected.r, label)
    assert_equal(p.g, expected.g, label)
    assert_equal(p.b, expected.b, label)


def _assert_near_color(
    c: Canvas, x: Int, y: Int, expected: Color, tolerance: Int, label: String
) raises:
    """`_assert_color()`'s tolerant sibling for a stroked position (an axis
    line, gridline, or annotation line, 1-2px wide) rather than a filled
    mark's interior. `render()`'s supersample-then-downsample
    (`Theme.raster_supersample`, default 3, theme.mojo) never lands a
    stroke that thin fully opaque in one output pixel, since its
    footprint straddles a downsample block unevenly; a filled region's
    interior averages to the exact color and can use `_assert_color()`.
    """
    var p = c.get_pixel(x, y)
    assert_true(
        abs(Int(p.r) - Int(expected.r)) <= tolerance
        and abs(Int(p.g) - Int(expected.g)) <= tolerance
        and abs(Int(p.b) - Int(expected.b)) <= tolerance,
        label
        + " (got ("
        + String(p.r)
        + ","
        + String(p.g)
        + ","
        + String(p.b)
        + "), expected within "
        + String(tolerance)
        + " of ("
        + String(expected.r)
        + ","
        + String(expected.g)
        + ","
        + String(expected.b)
        + "))",
    )


def _unique_categories(data: List[String]) -> List[String]:
    """Every distinct value in `data` in first-seen order, by a plain O(n^2)
    scan: a naive reference implementation kept as an oracle for
    `dataviz.plot._categorical_indices` and
    `dataviz.edges._edge_node_index`, which resolve the same domain in
    one hashed pass.
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
