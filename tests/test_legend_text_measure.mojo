"""A row legend's sections are spaced by measured text, not estimated (#573).

`_text_advance()` used to guess a label's width as
`byte_length * font_size * 0.62`. It was wrong two ways, and both are
checkable from the swatch positions in the rendered SVG, because each
section's x is the previous one's x plus that label's advance.

`byte_length` counts UTF-8 bytes, so a non-ASCII label was charged for
more characters than it has. And one advance per character is only right
for a monospaced font, which none of the defaults are.

Measured on a 900-pixel row legend, before and after:

| labels               | estimated | measured |
| -------------------- | --------- | -------- |
| `iiiiiiii` (8 bytes) | 91        | 57       |
| `WWWWWWWW` (8 bytes) | 91        | 127      |
| `aaaa` (4 bytes)     | 61        | 60       |
| `aaaa` accented (8)  | 91        | 60       |

The wide-glyph row is the visible defect: the estimate falls 36 pixels
short, so the next swatch is drawn 36 pixels inside the label before it.
The narrow row leaves a 34-pixel gap, and the accented row is charged
half again as much as the identical-looking ASCII one.
"""

from std.testing import TestSuite, assert_equal, assert_true

from canvas.text.font_cache import FontCache
from canvas.text.render import measure_text

from dataviz import LegendPosition, Plot, Theme, render_svg
from dataviz.core.text import _Scaled

comptime _SWATCH = 'width="14" height="14"'


def _theme() -> Theme:
    return Theme(legend_position=LegendPosition.TOP)


def _plot(labels: List[String]) raises -> Plot:
    """A scatter whose color channel is `labels`, legend along the top.

    The row legend is the only layout that uses `_text_advance()`; the
    column form measures its labels with `_max_label_width()` and always
    has.
    """
    var x = List[Float64]()
    var y = List[Float64]()
    var cat = List[String]()
    for i in range(12):
        x.append(Float64(i))
        y.append(Float64(i % 4) + 1.0)
        cat.append(labels[i % len(labels)])
    return (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cat)
        .theme(_theme())
        .size(900, 400)
    )


def _swatch_xs(labels: List[String]) raises -> List[Int]:
    """Where each legend swatch starts, left to right.

    Swatches are the only 14 by 14 rects in the document, which is how
    the existing legend-position tests find them too.
    """
    var svg = render_svg(_plot(labels)).to_string()
    var xs = List[Int]()
    var rest = svg
    while True:
        var at = rest.find(_SWATCH)
        if at == -1:
            break
        var head = String(rest[byte=0:at])
        var tag_at = head.rfind("<rect")
        if tag_at == -1:
            break
        var tag = String(head[byte=tag_at:])
        var x_at = tag.find('x="') + 3
        var x_end = tag.find('"', x_at)
        xs.append(Int(Float64(String(tag[byte=x_at:x_end]))))
        var tail = String(rest[byte = at + _SWATCH.byte_length() :])
        rest = tail
    return xs^


def _first_gap(labels: List[String]) raises -> Int:
    var xs = _swatch_xs(labels)
    if len(xs) < 2:
        raise Error(
            "expected at least two legend swatches, found " + String(len(xs))
        )
    return xs[1] - xs[0]


def test_labels_of_equal_byte_length_are_not_spaced_equally() raises:
    """The discriminating test.

    Eight narrow glyphs and eight wide ones are the same number of
    bytes, so any layout driven by `byte_length` gives them the same
    advance. They do not render the same width, so a layout driven by
    measurement must not.

    With the estimate in place both rows put their swatches at 60, 151
    and 242. That is the bug in one line.
    """
    var narrow: List[String] = ["iiiiiiii", "llllllll", "jjjjjjjj"]
    var wide: List[String] = ["WWWWWWWW", "MMMMMMMM", "QQQQQQQQ"]
    assert_equal(
        narrow[0].byte_length(),
        wide[0].byte_length(),
        "the two label sets must have equal byte length or this proves nothing",
    )
    var narrow_gap = _first_gap(narrow)
    var wide_gap = _first_gap(wide)
    assert_true(
        wide_gap > narrow_gap + 30,
        (
            "eight wide glyphs were given "
            + String(wide_gap)
            + " pixels and eight narrow ones "
            + String(narrow_gap)
            + "; a layout that counts bytes gives them the same number"
        ),
    )


def test_a_multibyte_label_is_not_charged_for_its_bytes() raises:
    """Four accented characters are eight UTF-8 bytes and four glyphs.

    Under the estimate they cost the same as eight ASCII characters, so
    the accented row was spaced at 91 pixels against the ASCII row's 61
    for labels that render within a pixel of each other.
    """
    var ascii: List[String] = ["aaaa", "aaab", "aaac"]
    var accented: List[String] = ["áááá", "ááéá", "ááíá"]
    assert_equal(
        accented[0].byte_length(),
        2 * ascii[0].byte_length(),
        "the accented labels must be twice the bytes or this proves nothing",
    )
    var ascii_gap = _first_gap(ascii)
    var accented_gap = _first_gap(accented)
    var drift = abs(accented_gap - ascii_gap)
    assert_true(
        drift <= 4,
        (
            "four accented glyphs were given "
            + String(accented_gap)
            + " pixels and four ASCII ones "
            + String(ascii_gap)
            + "; they render the same width, so counting bytes is what"
            " separates them"
        ),
    )


def test_the_next_swatch_clears_the_label_before_it() raises:
    """The property the spacing exists for, asserted directly.

    A section's swatch must start past the end of the previous label's
    rendered text. Under the estimate, eight wide glyphs overran their
    allotted space by about 36 pixels, so the swatch was drawn on top of
    the label and the label's text was then replayed over the swatch.
    """
    var wide: List[String] = ["WWWWWWWW", "MMMMMMMM", "QQQQQQQQ"]
    var xs = _swatch_xs(wide)
    assert_equal(len(xs), 3, "one swatch per category")

    var sc = _Scaled(_theme())
    var cache = FontCache()
    for i in range(len(xs) - 1):
        # The label starts a swatch and a gap past its own swatch.
        var label_x = xs[i] + sc.legend_swatch_size + sc.label_gap
        var label_end = (
            Float64(label_x)
            + measure_text(wide[i], sc.font_size, cache=cache).width
        )
        assert_true(
            Float64(xs[i + 1]) >= label_end,
            (
                "swatch "
                + String(i + 1)
                + " starts at "
                + String(xs[i + 1])
                + ", inside label "
                + String(i)
                + " which ends at "
                + String(label_end)
            ),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
