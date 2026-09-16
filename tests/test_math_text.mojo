"""Mathematical labels (#371): what the parser accepts and refuses,
where the layout puts a script or a fraction, and what reaches the
page through each backend.

The layout tests read the module's own named conventions -- a
superscript is `_SCRIPT_SCALE` of its base and `_SUP_RISE` above it --
rather than the numbers those stand for, so a deliberate change to a
convention is one edit, and an accidental one still fails.
"""

from std.math import pi
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.bounds import BoundsTarget
from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.text.font_discovery import FontSlant
from canvas.text.render import TextAlign, measure_text, measure_text_block

from dataviz import Plot, bar
from dataviz.core.mathtext import (
    _AXIS,
    _RELATION_SPACE,
    _SCRIPT_SCALE,
    _SUB_DROP,
    _SUP_RISE,
    _label_requests,
    _label_width,
    _layout_label,
    _needs_math,
    _reserve_height,
)
from dataviz.core.text import _TextRequest
from dataviz.core.theme import Theme
from dataviz.plot import (
    _replay_text_requests_bounds,
    render,
    render_svg,
    render_tight,
)
from _test_helpers import _count_color


comptime _SIZE = 20.0
comptime _INK = Color(30, 30, 30)


def _count(s: String, needle: String) -> Int:
    """Occurrences of `needle` in `s`."""
    var n = 0
    var i = 0
    while True:
        var f = s.find(needle, i)
        if f < 0:
            return n
        n += 1
        i = f + 1


def _width(label: String, mut cache: FontCache) raises -> Float64:
    return _layout_label(label, _SIZE, "Sans", False, cache=cache).width


def _xy() -> Tuple[List[Float64], List[Float64]]:
    var xs: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var ys: List[Float64] = [2.0, 4.0, 3.0, 5.0]
    return (xs^, ys^)


# ==== what is math and what is not ====


def test_a_label_needs_two_dollars_or_an_escape_to_be_math() raises:
    assert_true(not _needs_math("plain"))
    # One dollar is a price, not a delimiter.
    assert_true(not _needs_math("Cost $5"))
    assert_true(_needs_math("$x$"))
    assert_true(_needs_math("Mean $\\mu$ of it"))
    # An escaped dollar needs the parser to unescape it, and nothing more.
    assert_true(_needs_math("a \\$ b"))


def test_an_escaped_dollar_is_literal_upright_text() raises:
    var cache = FontCache()
    var box = _layout_label("a \\$ b", _SIZE, "Sans", False, cache=cache)
    assert_equal(len(box.runs), 1)
    assert_equal(box.runs[0].text, "a $ b")
    assert_true(box.runs[0].slant == FontSlant.NORMAL)


# ==== what the parser refuses, and how it says so ====


def test_errors_name_the_label_and_the_character() raises:
    var cache = FontCache()
    with assert_raises(contains="Math label '$\\foo$': unknown command \\foo"):
        _ = _layout_label("$\\foo$", _SIZE, "Sans", False, cache=cache)
    with assert_raises(contains="unbalanced $"):
        _ = _layout_label("$a$b$", _SIZE, "Sans", False, cache=cache)
    with assert_raises(contains="missing closing }"):
        _ = _layout_label("${x$", _SIZE, "Sans", False, cache=cache)
    with assert_raises(contains="nothing for ^ to attach to"):
        _ = _layout_label("$^2$", _SIZE, "Sans", False, cache=cache)
    with assert_raises(contains="a second ^ on the same atom"):
        _ = _layout_label("$x^2^3$", _SIZE, "Sans", False, cache=cache)
    with assert_raises(contains="at character 2"):
        _ = _layout_label("$^2$", _SIZE, "Sans", False, cache=cache)


def test_a_bad_label_raises_at_render_time_naming_itself() raises:
    var d = _xy()
    var plot = (
        Plot().mark_point().encode(x=d[0], y=d[1]).labels(title="$\\nope$")
    )
    with assert_raises(contains="Math label '$\\nope$'"):
        _ = render(plot)


# ==== where things land ====


def test_a_superscript_is_smaller_higher_and_to_the_right() raises:
    var cache = FontCache()
    var box = _layout_label("$x^2$", _SIZE, "Sans", False, cache=cache)
    assert_equal(len(box.runs), 2)
    assert_equal(box.runs[1].size, _SIZE * _SCRIPT_SCALE)
    assert_equal(box.runs[1].dy, -_SUP_RISE * _SIZE)
    assert_true(box.runs[1].dx > box.runs[0].dx)
    var plain = _layout_label("$x$", _SIZE, "Sans", False, cache=cache)
    assert_true(box.ascent > plain.ascent, "the script did not raise the box")


def test_a_subscript_is_smaller_and_lower() raises:
    var cache = FontCache()
    var box = _layout_label("$x_i$", _SIZE, "Sans", False, cache=cache)
    assert_equal(box.runs[1].size, _SIZE * _SCRIPT_SCALE)
    assert_equal(box.runs[1].dy, _SUB_DROP * _SIZE)
    var plain = _layout_label("$x$", _SIZE, "Sans", False, cache=cache)
    assert_true(
        box.descent > plain.descent, "the script did not deepen the box"
    )


def test_both_scripts_stack_on_one_column() raises:
    var cache = FontCache()
    var box = _layout_label("$x_i^2$", _SIZE, "Sans", False, cache=cache)
    assert_equal(len(box.runs), 3)
    assert_equal(box.runs[1].dx, box.runs[2].dx)
    assert_true(box.runs[1].dy < 0.0 and box.runs[2].dy > 0.0)


def test_a_fraction_stacks_around_a_rule_at_the_math_axis() raises:
    var cache = FontCache()
    var box = _layout_label("$\\frac{a}{b}$", _SIZE, "Sans", False, cache=cache)
    assert_equal(len(box.runs), 2)
    assert_equal(len(box.rules), 1)
    ref rule = box.rules[0]
    # Within an ulp rather than equal: `_AXIS * _SIZE` here is two
    # literals multiplied exactly at compile time, while the layout
    # multiplies a runtime Float64, and 6.6 is not representable.
    assert_true(
        abs(rule.dy + _AXIS * _SIZE) < 1e-9, "the rule is off the math axis"
    )
    assert_true(
        box.runs[0].dy < rule.dy and rule.dy < box.runs[1].dy,
        "numerator, rule and denominator are not in that order",
    )
    assert_equal(rule.width, box.width, "the rule does not span the fraction")
    var line = _layout_label("$a$", _SIZE, "Sans", False, cache=cache)
    assert_true(box.ascent + box.descent > line.ascent + line.descent)


def test_letters_and_lowercase_greek_are_italic_and_the_rest_upright() raises:
    var cache = FontCache()
    var box = _layout_label(
        "$x2\\alpha\\Omega\\mathrm{y}$", _SIZE, "Sans", False, cache=cache
    )
    assert_equal(len(box.runs), 5)
    assert_true(box.runs[0].slant == FontSlant.ITALIC, "a variable is italic")
    assert_true(box.runs[1].slant == FontSlant.NORMAL, "a digit is upright")
    assert_true(
        box.runs[2].slant == FontSlant.ITALIC, "lowercase Greek is italic"
    )
    assert_true(
        box.runs[3].slant == FontSlant.NORMAL, "capital Greek is upright"
    )
    assert_true(
        box.runs[4].slant == FontSlant.NORMAL, "\\mathrm forces upright"
    )


def test_symbols_mean_what_their_names_say() raises:
    # The three that are easy to get almost right: the ring operator is
    # not a degree sign, and the two ellipses sit at different heights.
    var cache = FontCache()
    var box = _layout_label(
        "$\\circ\\ldots\\cdots\\degree$", _SIZE, "Sans", False, cache=cache
    )
    assert_equal(box.runs[0].text, "∘")
    assert_equal(box.runs[1].text, "…")
    assert_equal(box.runs[2].text, "⋯")
    assert_equal(box.runs[3].text, "°")


def test_a_radical_rules_over_its_argument() raises:
    var cache = FontCache()
    var box = _layout_label("$\\sqrt{x}$", _SIZE, "Sans", False, cache=cache)
    assert_equal(len(box.runs), 2)
    assert_equal(len(box.rules), 1)
    ref rule = box.rules[0]
    ref arg = box.runs[1]
    assert_true(rule.dy < arg.dy, "the rule is not above the argument")
    assert_true(rule.dx < arg.dx, "the rule does not start over the sign")
    assert_true(
        rule.dx + rule.width >= arg.dx + _width("$x$", cache),
        "the rule stops short of the argument's end",
    )
    var bare = _layout_label("$x$", _SIZE, "Sans", False, cache=cache)
    assert_true(box.ascent > bare.ascent, "the rule did not raise the box")


def test_relations_get_room_and_a_unary_minus_does_not() raises:
    var cache = FontCache()
    # Room on both sides of the "=", so the sum of the parts falls short
    # of the whole by exactly that.
    var whole = _width("$a=b$", cache)
    var parts = (
        _width("$a$", cache) + _width("$=$", cache) + _width("$b$", cache)
    )
    var room = whole - parts
    var expected = 2.0 * _RELATION_SPACE * _SIZE
    assert_true(
        abs(room - expected) < 1.0,
        "relation room is " + String(room) + ", expected " + String(expected),
    )
    # A leading minus is a sign, not an operator, and hugs its operand.
    var unary = (
        _width("$-t$", cache) - _width("$-$", cache) - _width("$t$", cache)
    )
    assert_true(
        abs(unary) < 0.5, "a unary minus was given room: " + String(unary)
    )


# ==== the two questions layout asks ====


def test_reserved_height_is_the_size_for_plain_and_the_box_for_math() raises:
    var cache = FontCache()
    assert_equal(_reserve_height("plain", 18.0, "Sans", False, cache=cache), 18)
    var script = _reserve_height("$x^2$", 18.0, "Sans", False, cache=cache)
    var frac = _reserve_height(
        "$\\frac{a}{b}$", 18.0, "Sans", False, cache=cache
    )
    assert_true(script > 18, "a superscript needs more than one line")
    assert_true(frac > script, "a fraction needs more than a superscript")


def test_a_plain_labels_width_is_exactly_what_it_was() raises:
    var cache = FontCache()
    assert_equal(
        _label_width("Response time", 12.0, "Sans", False, cache=cache),
        measure_text("Response time", 12.0, cache=cache).width,
    )


# ==== the requests ====


def test_a_plain_label_is_one_unchanged_request() raises:
    var cache = FontCache()
    var reqs = _label_requests(
        "plain",
        10,
        20,
        12.0,
        _INK,
        TextAlign.CENTER,
        "Sans",
        True,
        0.5,
        cache=cache,
    )
    assert_equal(len(reqs), 1)
    assert_equal(reqs[0].text, "plain")
    assert_equal(reqs[0].x, 10)
    assert_equal(reqs[0].y, 20)
    assert_true(
        reqs[0].align == TextAlign.CENTER, "alignment is passed through"
    )
    assert_true(reqs[0].bold)
    assert_equal(reqs[0].rotation, 0.5)
    assert_true(reqs[0].slant == FontSlant.NORMAL)
    assert_true(not reqs[0].is_rule())


def test_a_centered_expression_straddles_its_anchor_as_left_runs() raises:
    var cache = FontCache()
    var reqs = _label_requests(
        "$x^2$",
        100,
        50,
        _SIZE,
        _INK,
        TextAlign.CENTER,
        "Sans",
        False,
        0.0,
        cache=cache,
    )
    assert_equal(len(reqs), 2)
    for r in reqs:
        assert_true(
            r.align == TextAlign.LEFT, "each run is placed, not aligned"
        )
    assert_true(reqs[0].x < 100 and reqs[1].x > 100)
    assert_true(reqs[0].slant == FontSlant.ITALIC)
    assert_true(reqs[1].y < reqs[0].y, "the script sits above the baseline")


def test_rotation_turns_the_script_with_the_baseline() raises:
    # A quarter turn counterclockwise, as the y caption uses: along the
    # baseline is now up the page, and above it is now to the left.
    var cache = FontCache()
    var reqs = _label_requests(
        "$x^2$",
        100,
        200,
        _SIZE,
        _INK,
        TextAlign.LEFT,
        "Sans",
        False,
        -pi / 2.0,
        cache=cache,
    )
    assert_true(
        reqs[1].y < reqs[0].y, "the script is further along the baseline"
    )
    assert_true(reqs[1].x < reqs[0].x, "the script is on the ascent side")
    assert_equal(reqs[1].rotation, -pi / 2.0)


def test_a_rule_request_is_a_rule() raises:
    var rule = _TextRequest.rule(1, 2, 30, 2, 1.5, _INK)
    assert_true(rule.is_rule())
    assert_equal(rule.rule_x2, 30)
    assert_equal(rule.rule_thickness, 1.5)
    var text = _TextRequest(1, 2, "t", _INK, 10.0, TextAlign.LEFT, "Sans")
    assert_true(not text.is_rule())


# ==== what reaches the page ====


def test_a_math_title_becomes_one_text_element_per_run_in_svg() raises:
    var d = _xy()
    var math = render_svg(
        Plot().mark_point().encode(x=d[0], y=d[1]).labels(title="$E = mc^2$")
    ).to_string()
    var plain = render_svg(
        Plot().mark_point().encode(x=d[0], y=d[1]).labels(title="E = mc2")
    ).to_string()
    # E, =, mc, 2: four elements where the plain title is one.
    assert_equal(_count(math, "<text") - _count(plain, "<text"), 3)
    assert_equal(_count(math, 'font-style="italic"'), 2, "E and mc are italic")
    assert_true('font-size="12.600"' in math, "the 2 is 0.7 of 18")


def test_math_reaches_legend_annotation_and_category_ticks() raises:
    var xs: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var ys: List[Float64] = [2.0, 4.0, 3.0, 5.0]
    var cat: List[String] = ["$\\mu$", "$\\sigma^2$", "$\\mu$", "$\\sigma^2$"]
    var svg = render_svg(
        Plot()
        .mark_point()
        .encode(x=xs, y=ys, color_categories=cat)
        .annotate_point(4.0, 5.0, label="$x_0$")
    ).to_string()
    assert_true(
        "σ" in svg and "μ" in svg, "legend entries are laid out as math"
    )
    # The legend draws at the theme's font size, and its superscript at
    # 0.7 of that. Pinned to the default so the expected string is
    # exact; if the default moves, this says why the test moved.
    assert_equal(Theme().font_size, 12.0)
    assert_true(
        'font-size="8.400"' in svg, "the legend's superscript is 0.7 of 12"
    )
    assert_true(">0</text>" in svg, "the annotation's subscript is its own run")
    var cats: List[String] = ["$\\alpha$", "b"]
    var vals: List[Float64] = [3.0, 1.0]
    var ticks = render_svg(bar(cats, vals)).to_string()
    assert_true("α" in ticks, "a category tick is laid out as math")


def test_the_bounds_probe_sees_every_run_of_an_expression() raises:
    # The probe's box has to be the union of what each run will ink,
    # measured the way the run will be drawn. Compared directly, with
    # no crop in between: `_tight_box` adds no padding, but a figure
    # has other ink around a label, and a probe that dropped one run
    # of a caption could still sit inside the box the rest of the
    # figure sets. At size 12 the scripts are 8.4, so a probe that
    # skipped small runs, or italic ones, shrinks this by whole pixels.
    var cache = FontCache()
    var reqs = _label_requests(
        "$x_i^2 = y$",
        100,
        60,
        12.0,
        _INK,
        TextAlign.LEFT,
        "Sans",
        False,
        0.0,
        cache=cache,
    )
    var probe = BoundsTarget(300, 120)
    _replay_text_requests_bounds(probe, reqs, cache)
    assert_true(probe.has_ink())
    var got = probe.ink_pixels()
    var x0 = 1.0e9
    var y0 = 1.0e9
    var x1 = -1.0e9
    var y1 = -1.0e9
    for r in reqs:
        if r.is_rule():
            continue
        var b = measure_text_block(
            r.text, r.size, family="Sans", slant=r.slant, cache=cache
        )
        x0 = min(x0, Float64(r.x) + b.x)
        y0 = min(y0, Float64(r.y) + b.y)
        x1 = max(x1, Float64(r.x) + b.x + b.width)
        y1 = max(y1, Float64(r.y) + b.y + b.height)
    assert_true(
        abs(Float64(got[0]) - x0) <= 1.0, "the probe's left edge is off"
    )
    assert_true(abs(Float64(got[1]) - y0) <= 1.0, "the probe's top edge is off")
    assert_true(
        abs(Float64(got[0] + got[2]) - x1) <= 1.0,
        "the probe's right edge is off",
    )
    assert_true(
        abs(Float64(got[1] + got[3]) - y1) <= 1.0,
        "the probe's bottom edge is off",
    )


def test_cropping_to_the_measured_bounds_loses_no_text() raises:
    # The tight crop is cut from what BoundsTarget measured, so a probe
    # that skipped the labels altogether would lose text ink here.
    #
    # What this cannot see: a probe that skips one *run* of a caption.
    # It passed with the probe ignoring every run under 10 pixels,
    # because the rest of the figure's ink already set a box the
    # skipped script sat inside. The test above is the one that fails
    # for that; this one stays for the gross case.
    var d = _xy()
    var theme = Theme()
    var plot = (
        Plot()
        .mark_point()
        .encode(x=d[0], y=d[1])
        .theme(theme)
        .labels(title="$\\frac{\\Delta y}{\\Delta x}$", y_title="$\\sigma_x^2$")
    )
    var full = render(plot)
    var tight = render_tight(plot)
    assert_true(tight.height < full.height, "the crop removed nothing")
    assert_equal(
        _count_color(tight, theme.text_color),
        _count_color(full, theme.text_color),
        "cropping to the measured bounds lost text ink",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
