"""Legend layout: swatch spacing from measured text, and the horizontal legend's
centered tick.

One module rather than 2: every test module pays the same dependency
compilation, so the suite is organized by family (#605).
"""

from std.testing import TestSuite, assert_equal, assert_true
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.text.render import measure_text
from dataviz import LegendPosition, Plot, Theme, render_svg, scatter
from dataviz.core.legend_position import LegendPosition
from dataviz.core.text import _Scaled
from dataviz.core.theme import Theme
from dataviz.plot import Plot, render


# ==== from test_legend_text_measure.mojo ====
# A row legend's sections are spaced by measured text, not estimated (#573).
#
# `_text_advance()` used to guess a label's width as
# `byte_length * font_size * 0.62`. It was wrong two ways, and both are
# checkable from the swatch positions in the rendered SVG, because each
# section's x is the previous one's x plus that label's advance.
#
# `byte_length` counts UTF-8 bytes, so a non-ASCII label was charged for
# more characters than it has. And one advance per character is only right
# for a monospaced font, which none of the defaults are.
#
# Measured on a 900-pixel row legend, before and after:
#
# | labels               | estimated | measured |
# | -------------------- | --------- | -------- |
# | `iiiiiiii` (8 bytes) | 91        | 57       |
# | `WWWWWWWW` (8 bytes) | 91        | 127      |
# | `aaaa` (4 bytes)     | 61        | 60       |
# | `aaaa` accented (8)  | 91        | 60       |
#
# The wide-glyph row is the visible defect: the estimate falls 36 pixels
# short, so the next swatch is drawn 36 pixels inside the label before it.
# The narrow row leaves a 34-pixel gap, and the accented row is charged
# half again as much as the identical-looking ASCII one.


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


# ==== from test_h_legend_center_tick.mojo ====
# A horizontal color legend marks a centered ramp's neutral point (#526).
#
# `Plot.scale_color_center()` pins a diverging ramp's neutral color to a
# value and lets the two arms be different sizes. The vertical legend draws
# a third label at that center. The row form, used for
# `LegendPosition.TOP`/`BOTTOM`, drew nothing, so the chart showed a
# gradient with two end numbers and no way to read where the center went.
#
# It now draws a tick on the bar instead of a label under it: a row legend
# exists to cost no height, and a label stacked below would spend exactly
# what the layout saved.
#
# These read pixels rather than SVG `<text>`, because the tick carries no
# text. The discriminator is a column of `text_color` inside the bar's own
# rows, which the gradient never produces on its own.


def _xs() -> List[Float64]:
    var x = List[Float64]()
    for i in range(12):
        x.append(Float64(i))
    return x^


def _ys() -> List[Float64]:
    var y = List[Float64]()
    for i in range(12):
        y.append(Float64(i % 5) + 1.0)
    return y^


def _values(lo: Float64, hi: Float64) -> List[Float64]:
    """A color channel spanning `lo` to `hi`, so the legend's domain is
    known exactly rather than inferred from the data's shape.

    Args:
        lo: The first value.
        hi: The last value.

    Returns:
        Twelve values from `lo` to `hi`.
    """
    var c = List[Float64]()
    for i in range(12):
        c.append(lo + (hi - lo) * Float64(i) / 11.0)
    return c^


def _theme_h_legend_center_tick() -> Theme:
    return Theme(legend_position=LegendPosition.BOTTOM, show_gridlines=False)


def _tick_columns(c: Canvas, theme: Theme) -> List[Int]:
    """Every x where a full vertical run of `text_color` appears, which
    is what the tick draws and the gradient does not.

    Scans the whole canvas rather than an assumed bar rectangle: the
    legend's position is layout, and a test that hard-codes it breaks
    whenever the layout moves rather than when the tick does.

    Args:
        c: The rendered chart.
        theme: Supplies the tick's color.

    Returns:
        The x positions carrying a run of at least 6 such pixels.
    """
    var tc = theme.text_color
    var cols = List[Int]()
    for x in range(c.width):
        var run = 0
        var best = 0
        for y in range(c.height):
            var p = c.get_pixel(x, y)
            if p.r == tc.r and p.g == tc.g and p.b == tc.b:
                run += 1
                if run > best:
                    best = run
            else:
                run = 0
        if best >= 6:
            cols.append(x)
    return cols^


def _centered(lo: Float64, hi: Float64, center: Float64) raises -> Canvas:
    var p = (
        scatter(
            _xs(),
            _ys(),
            theme=_theme_h_legend_center_tick(),
            width=420,
            height=300,
        )
        .encode(x=_xs(), y=_ys(), color=_values(lo, hi))
        .scale_color_center(center)
    )
    return render(p^)


def _uncentered(lo: Float64, hi: Float64) raises -> Canvas:
    var p = scatter(
        _xs(), _ys(), theme=_theme_h_legend_center_tick(), width=420, height=300
    ).encode(x=_xs(), y=_ys(), color=_values(lo, hi))
    return render(p^)


def _lowest_frame_row(c: Canvas, tc: Color) -> Int:
    """The last row carrying a long horizontal run of `tc`, which is the
    axis frame's bottom line.

    Module level rather than nested: a nested `def` in Mojo 1.0 cannot
    capture, so the color has to be a parameter.

    Args:
        c: The rendered chart.
        tc: The frame's color.

    Returns:
        The row index, or -1 if no row qualifies.
    """
    var found = -1
    for y in range(c.height):
        var run = 0
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == tc.r and p.g == tc.g and p.b == tc.b:
                run += 1
        if run > 40:
            found = y
    return found


def test_a_centered_ramp_draws_a_tick_an_uncentered_one_does_not() raises:
    # The control matters more than the positive here: text glyphs and
    # the axis frame are also drawn in text_color, so "found a column"
    # only means something against the same chart without a center.
    var with_center = len(
        _tick_columns(
            _centered(-10.0, 30.0, 0.0), _theme_h_legend_center_tick()
        )
    )
    var without = len(
        _tick_columns(_uncentered(-10.0, 30.0), _theme_h_legend_center_tick())
    )
    assert_true(
        with_center > without,
        "centering added no vertical run: "
        + String(with_center)
        + " vs "
        + String(without),
    )


def test_the_tick_sits_off_middle_when_the_arms_are_asymmetric() raises:
    # The whole reason the tick exists. On -10..30 centered at 0 the
    # neutral point is a quarter along, so a tick drawn at the bar's
    # midpoint would be wrong while still being a tick.
    var near = _tick_columns(
        _centered(-10.0, 30.0, 0.0), _theme_h_legend_center_tick()
    )
    var far = _tick_columns(
        _centered(-10.0, 30.0, 20.0), _theme_h_legend_center_tick()
    )
    assert_true(len(near) > 0, "no tick for center 0")
    assert_true(len(far) > 0, "no tick for center 20")

    # Compare the rightmost new column in each: moving the center from
    # 0 to 20 must move the tick right.
    var a = near[len(near) - 1]
    var b = far[len(far) - 1]
    assert_true(
        b > a,
        "moving the center right did not move the tick right: "
        + String(a)
        + " then "
        + String(b),
    )


def test_the_tick_costs_no_height() raises:
    # The reason it is a tick and not a label. The rendered canvas is a
    # fixed size, so the claim is about the legend's own row height:
    # the chart body must not shrink when a center is added.
    var plain = _uncentered(-10.0, 30.0)
    var centered = _centered(-10.0, 30.0, 0.0)
    assert_equal(plain.width, centered.width, "width")
    assert_equal(plain.height, centered.height, "height")

    # The axis frame's lowest row is where the plot rect ends. If the
    # legend had grown, the frame would have been squeezed upward.
    assert_equal(
        _lowest_frame_row(plain, _theme_h_legend_center_tick().text_color),
        _lowest_frame_row(centered, _theme_h_legend_center_tick().text_color),
        "the plot rect moved, so the legend changed height",
    )


def test_a_center_all_but_on_the_domain_edge_draws_no_tick() raises:
    # A tick within its own width of the bar's end reads as a border
    # rather than a mark, so it is skipped.
    #
    # The center is 0.1 rather than 0.0 because `scale_color_center()`
    # already rejects a center on the domain boundary outright ("must
    # lie strictly inside the color domain"). So the exact-edge case is
    # unreachable through the public API and the guard in the drawing
    # code is only for centers near the edge, which are allowed. This
    # test pins the reachable half; the API owns the other.
    var edge = len(
        _tick_columns(_centered(0.0, 30.0, 0.1), _theme_h_legend_center_tick())
    )
    var plain = len(
        _tick_columns(_uncentered(0.0, 30.0), _theme_h_legend_center_tick())
    )
    assert_equal(edge, plain, "a tick was drawn at the bar's end")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
