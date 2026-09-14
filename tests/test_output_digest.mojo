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

Run `pixi run digest-update` to regenerate the file after a change you
meant to make. Read the diff before committing it: that is the review.
"""

from std.testing import TestSuite, assert_equal, assert_true

from canvas.buffer import Canvas

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


def _digest_lines() raises -> List[String]:
    """One line per mark: `name raster_digest svg_bytes svg_digest`.

    Both backends, because they diverge in different ways. A raster
    regression moves pixels; an SVG one moves elements, which the byte
    count alone would sometimes miss and the hash will not.
    """
    var out = List[String]()
    for value in range(Mark.COUNT):
        var mark = Mark(value)
        # One Plot, both backends. Building it twice doubled the cost of
        # the slowest module in the suite for nothing.
        var plot = _representative_plot(mark)
        var raster = render(plot)
        var svg = render_svg(plot).to_string()
        out.append(
            mark.name()
            + " "
            + String(_canvas_digest(raster))
            + " "
            + String(svg.byte_length())
            + " "
            + String(_text_digest(svg))
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
            + " marks and this run produced "
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
            + " mark(s) render differently than the committed digest."
            + " If that was the point, run `pixi run digest-update` and"
            + " include the diff in the same commit:"
            + detail
        )


def test_the_digest_file_covers_every_mark() raises:
    """The file could drift into listing fewer marks than exist, which
    would narrow the gate rather than fail it.

    Reads the file rather than rendering again: the sweep above is the
    slowest thing in the suite, and running it twice to count its own
    output would double that for nothing.
    """
    var f = open("tests/output_digest.txt", "r")
    var text = f.read()
    f.close()
    var listed = 0
    for line in text.split("\n"):
        var trimmed = String(String(line).strip())
        if trimmed.byte_length() > 0 and not trimmed.startswith("#"):
            listed += 1
    assert_equal(listed, Mark.COUNT, "one digest line per Mark value")
    assert_true(Mark.COUNT > 40, "the mark list collapsed")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
