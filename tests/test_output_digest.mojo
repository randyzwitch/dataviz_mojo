"""Every mark's rendered output, against a committed fingerprint (#570).

The rest of the suite asserts properties: this pixel is not the
background, these two renders differ, that value lands in this column.
None of it would notice if every chart in the library shifted a pixel,
or if a fill changed shade.

That gap has a cost that was paid twice before this existed. A
canvas_mojo release says "no rendered-output change to any existing
scene", and checking that claim against *this* library meant writing a
throwaway program both times, for v0.34.0 and again for v0.35.0. Both
times it held. Neither time was it checked by anything a reviewer could
see.

So: one digest per mark, committed to `tests/output_digest.txt`. A
deliberate rendering change updates that file in the same commit, and
the diff says which charts moved, which is the useful half. Not "did
anything change" but "these four changed, and here is the change that
changed them".

The marks come from `_mark_registry`, shared with
`test_backend_equivalence`, which walks every `Mark` value and raises
for one without an entry. So a new mark is covered here the day it is
added, without anybody remembering to add it.

The compositions come from `_composition_registry` and do not get that
for free: a facet grid, a `render_grid` figure, a pairplot, a jointplot
and a clustermap are functions, not enum values, so there is nothing to
walk (#600). That list is hand-maintained and says so. It exists
because a composition is exactly where a change is least likely to be
caught elsewhere -- the per-mark tests pin pixels, while a
composition's own tests assert that this cell is left of that one --
and #588 proved the gap by changing facet rendering with the digest
none the wiser.

Run `pixi run digest-update` to regenerate the file after a change you
meant to make. Read the diff before committing it: that is the review.
"""

from std.testing import TestSuite, assert_equal, assert_true

from canvas.buffer import Canvas

from _composition_registry import (
    _COMPOSITION_COUNT,
    _composition_name,
    _composition_raster,
    _composition_svg,
    _dark_ground,
)
from _mark_registry import _H, _W, _representative_plot
from dataviz.core.mark import Mark
from dataviz.plot import render, render_svg


def _canvas_digest(c: Canvas) -> Int:
    """A position-weighted checksum of every pixel.

    Weighted by position so that two pixels swapping places changes it.
    A plain channel sum would not, and "the same ink somewhere else" is
    exactly the regression this is for.
    """
    var total = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            total += (
                Int(p.r) * 7919 + Int(p.g) * 104729 + Int(p.b) * 1299709
            ) * (x + y * 31 + 1)
    return total


def _text_digest(s: String) -> Int:
    var h = 0
    var i = 0
    for b in s.bytes():
        h = (h * 131 + Int(b) * (i + 1)) % 1000000007
        i += 1
    return h


def _line(name: String, raster: Canvas, svg: String) -> String:
    """One digest line: `name raster_digest svg_bytes svg_digest`.

    Both backends, because they diverge in different ways. A raster
    regression moves pixels; an SVG one moves elements, which the byte
    count alone would sometimes miss and the hash will not.

    **PDF is deliberately not here**, though #372 asks for an
    SVG-against-PDF comparison and the sweep already renders one. A PDF
    embeds the font program itself, and the CI matrix installs DejaVu
    from `apt` on Linux and from `brew` on macOS -- the same family,
    the same glyph outlines (the raster digests match exactly across
    both), but not the same file bytes. Adding the column turned every
    macOS run red on all 66 figures for a difference that is not a
    regression. See #631 for what a platform-stable PDF gate would
    need.
    """
    return (
        name
        + " "
        + String(_canvas_digest(raster))
        + " "
        + String(svg.byte_length())
        + " "
        + String(_text_digest(svg))
    )


def _digest_lines() raises -> List[String]:
    """Every mark, then every composition, in that order.

    One list rather than two files: the gate below reads it
    positionally, and a single ordered list is what makes "these four
    changed" readable in a diff.
    """
    var out = List[String]()
    for value in range(Mark.COUNT):
        var mark = Mark(value)
        # One Plot, both backends. Building it twice doubled the cost of
        # the slowest module in the suite for nothing.
        var plot = _representative_plot(mark)
        out.append(
            _line(mark.name(), render(plot), render_svg(plot).to_string())
        )
    for index in range(_COMPOSITION_COUNT):
        # Two calls rather than one, unlike a mark: a composition's two
        # backends are separate entry points taking their own arguments,
        # not one `Plot` handed to two renders.
        out.append(
            _line(
                _composition_name(index),
                _composition_raster(index),
                _composition_svg(index).to_string(),
            )
        )
    return out^


def test_every_mark_renders_what_it_rendered_before() raises:
    """The gate. A mismatch is either a regression or a change somebody
    meant to make, and the two are told apart by whether the commit says
    so.
    """
    var got = _digest_lines()
    var f = open("tests/output_digest.txt", "r")
    var want_text = f.read()
    f.close()

    var want = List[String]()
    for line in want_text.split("\n"):
        var trimmed = String(String(line).strip())
        if trimmed.byte_length() > 0 and not trimmed.startswith("#"):
            want.append(trimmed^)

    assert_equal(
        len(got),
        len(want),
        (
            "the digest file has "
            + String(len(want))
            + " entries and this run produced "
            + String(len(got))
            + "; run `pixi run digest-update`"
        ),
    )
    var mismatches = List[String]()
    for i in range(len(got)):
        if got[i] != want[i]:
            mismatches.append("  want " + want[i] + "\n  got  " + got[i])
    if len(mismatches) > 0:
        var detail = String("")
        for m in mismatches:
            detail += "\n" + m
        raise Error(
            String(len(mismatches))
            + " figure(s) render differently than the committed digest."
            + " If that was the point, run `pixi run digest-update` and"
            + " include the diff in the same commit:"
            + detail
        )


def test_the_digest_file_covers_every_mark_and_composition() raises:
    """The file could drift into listing fewer entries than exist, which
    would narrow the gate rather than fail it.

    Reads the file rather than rendering again: the sweep above is the
    slowest thing in the suite, and running it twice to count its own
    output would double that for nothing.

    The two halves are told apart by the `Mark.` prefix, which is what
    `Mark.name()` produces and no composition name has.
    """
    var f = open("tests/output_digest.txt", "r")
    var text = f.read()
    f.close()
    var marks = 0
    var compositions = 0
    for line in text.split("\n"):
        var trimmed = String(String(line).strip())
        if trimmed.byte_length() == 0 or trimmed.startswith("#"):
            continue
        if trimmed.startswith("Mark."):
            marks += 1
        else:
            compositions += 1
    assert_equal(marks, Mark.COUNT, "one digest line per Mark value")
    assert_true(Mark.COUNT > 40, "the mark list collapsed")
    assert_equal(
        compositions,
        _COMPOSITION_COUNT,
        (
            "one digest line per composition; this list is hand-maintained,"
            " see tests/_composition_registry.mojo"
        ),
    )


def test_the_facet_figure_can_see_its_own_background() raises:
    """The composition entries are only worth their runtime if they can
    see the changes they were added for, and the first one they were
    added for is #588: the figure ground `render_facets` fills so a
    partial last row is not a white hole.

    A figure on the default theme cannot see that change at all. The
    canvas is already white when the fill runs, so on white the fill
    writes white over white and moves no pixels -- which is why a
    deliberate facet-rendering change slipped past the digest in the
    first place. Shortening that fill by a row was tried against a
    default-theme facet figure while writing this, and the digest stayed
    green.

    So `_dark_ground` is load-bearing, and this says so out loud. Point
    the facet registry entry back at the default theme and this fails,
    rather than the digest quietly going blind again.
    """
    var blank = Canvas(8, 8)
    var fresh = blank.get_pixel(0, 0)
    var ground = _dark_ground().background
    assert_true(
        ground.r != fresh.r or ground.g != fresh.g or ground.b != fresh.b,
        (
            "the facet figure's background is the color a fresh canvas"
            " already is, so filling it moves no pixels and the digest"
            " cannot see a figure-background change"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
