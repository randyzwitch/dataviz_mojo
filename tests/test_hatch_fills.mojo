"""`Theme.fill_pattern_by_category` (#842): a `HatchStyle` over every
fill of the marks that fill one shape per category or series, legend
swatches included.

The central check is containment, read off the raster: turning the
patterns on may only change pixels that were already inside a fill, or
at most one pixel beyond one, the antialiased edge. A hatch line that
leaked across a wedge's straight edge or past a bar's end would change
background pixels far from any fill, and this fails. It also checks
that every mark draws a pattern at all, that the first category stays
solid, and that the SVG gains lines only when the flag is on.
"""

from std.testing import TestSuite, assert_equal, assert_true

from canvas.buffer import Canvas
from canvas.color import Color
from _mark_registry import _representative_plot
from dataviz import HatchStyle, render, render_svg
from dataviz.chart import AnyChart
from dataviz.core.hatch import _hatch_for_index
from dataviz.core.mark import Mark


def _marks() -> List[Mark]:
    return [
        Mark.ARC,
        Mark.STACKED_BAR,
        Mark.GROUPED_BAR,
        Mark.FUNNEL,
        Mark.STREAMGRAPH,
        Mark.TREEMAP,
        Mark.MARIMEKKO,
        Mark.NIGHTINGALE,
        Mark.POLAR_BAR,
        Mark.POPULATION_PYRAMID,
        Mark.SUNBURST,
    ]


def _patterned(mark: Mark) raises -> AnyChart:
    var p = _representative_plot(mark)
    p.settings.theme.fill_pattern_by_category = True
    return p^


def _near_ink(c: Canvas, x: Int, y: Int, bg: Color) -> Bool:
    """Whether (x, y) or one of its eight neighbors is not background."""
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            var nx = x + dx
            var ny = y + dy
            if nx < 0 or ny < 0 or nx >= c.width or ny >= c.height:
                continue
            if c.get_pixel(nx, ny) != bg:
                return True
    return False


def test_patterns_stay_inside_their_fills() raises:
    var report = String()
    for mark in _marks():
        var plain = _representative_plot(mark)
        var bg = plain.settings.theme.background
        var off = render(plain)
        var on = render(_patterned(mark))
        var changed = 0
        var leaked = 0
        for y in range(off.height):
            for x in range(off.width):
                if off.get_pixel(x, y) == on.get_pixel(x, y):
                    continue
                changed += 1
                if not _near_ink(off, x, y, bg):
                    leaked += 1
        if changed == 0:
            report += mark.name() + " drew no pattern; "
        if leaked > 0:
            report += (
                mark.name()
                + " changed "
                + String(leaked)
                + " background pixels away from any fill; "
            )
    assert_equal(report, "")


def test_the_flag_is_off_by_default_and_adds_lines_only_when_on() raises:
    for mark in _marks():
        var plain = _representative_plot(mark)
        assert_true(not plain.settings.theme.fill_pattern_by_category)
        var off = render_svg(plain).to_string()
        var on = render_svg(_patterned(mark)).to_string()
        var off_lines = off.count("<line") + off.count("<circle")
        var on_lines = on.count("<line") + on.count("<circle")
        assert_true(on_lines > off_lines, mark.name())


def test_the_first_category_stays_solid() raises:
    assert_true(_hatch_for_index(0) == HatchStyle.NONE)
    for i in range(1, 8):
        assert_true(_hatch_for_index(i) != HatchStyle.NONE)
    assert_true(_hatch_for_index(8) == HatchStyle.NONE)


def test_every_style_has_a_name() raises:
    for i in range(8):
        assert_true(HatchStyle(i).name() != "HatchStyle(" + String(i) + ")")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
