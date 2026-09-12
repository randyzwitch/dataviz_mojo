"""Every mark actually puts ink on a raster canvas.

The assertion looks trivial and is not. canvas's `begin_batch()` /
`end_batch()` records shapes and draws them at `end_batch`, and reads
are *not* ordered against a pending batch. `render()` ends with

    _render_into(scratch, plot, ...)
    return downsample(scratch, factor)

and `downsample` is a read, so a `begin_batch()` that never closes --
an unbalanced pair, or a loop with an early `return` between them --
produces a chart with the mark silently missing. No error, and only on
the raster backend, since the vector ones make both calls no-ops.

Counting *any* non-background pixel would not catch that: axes,
gridlines and text are drawn outside a mark's loop and would still be
there. So the theme below paints all of that in the background color,
leaving the mark's own geometry as the only thing that can differ from
the background.

Walks `Mark(0)` through `Mark(Mark.COUNT - 1)` off the same registry the
backend-equivalence sweep uses, so a new mark is covered without being
added here.
"""

from std.testing import assert_true, TestSuite

from canvas.buffer import Canvas
from canvas.color import Color

from dataviz.core.mark import Mark
from dataviz.plot import render
from dataviz.core.theme import Theme
from test_backend_equivalence import _representative_plot


comptime _WHITE = Color(255, 255, 255)
comptime _INK_W = 200
comptime _INK_H = 150


def _chrome_free_theme() -> Theme:
    """A theme whose every non-mark ink is the background color.

    Gridlines and the legend are switched off outright; the axis, tick
    and text colors are painted white on white, which is simpler than
    hunting for a switch per element and stays correct if new chrome is
    added later.
    """
    return Theme(
        background=_WHITE,
        axis_color=_WHITE,
        gridline_color=_WHITE,
        minor_gridline_color=_WHITE,
        text_color=_WHITE,
        show_gridlines=False,
        show_legend=False,
    )


def _has_ink(c: Canvas) -> Bool:
    """Whether any pixel is not the background, i.e. the mark drew.

    Returns on the first such pixel rather than counting them all: the
    assertion only needs presence, and counting every pixel of every
    mark made this sweep the slowest module in the suite.
    """
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r != _WHITE.r or p.g != _WHITE.g or p.b != _WHITE.b:
                return True
    return False


def test_every_mark_draws_ink_on_raster() raises:
    """No mark renders an empty canvas.

    The failure this exists for is a mark whose whole geometry vanishes
    while the render still succeeds -- see this module's docstring.
    """
    for value in range(Mark.COUNT):
        var plot = _representative_plot(Mark(value))
        plot._theme = _chrome_free_theme()
        # Render small. Raster cost is per device pixel and this sweep
        # renders every mark, so the default size made this the slowest
        # module in the suite for no extra coverage -- presence of ink
        # does not depend on the canvas being large.
        plot.width = _INK_W
        plot.height = _INK_H
        var c = render(plot)
        assert_true(
            _has_ink(c),
            "mark "
            + Mark(value).name()
            + " drew no ink on a raster canvas -- if a draw loop was"
            + " recently wrapped in begin_batch(), check that every path"
            + " out of it reaches end_batch()",
        )

    # A sweep over an empty range would pass without checking anything.
    assert_true(Mark.COUNT > 0, "Mark.COUNT is zero -- the sweep ran no marks")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
