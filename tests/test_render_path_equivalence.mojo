"""The two raster render paths must agree, pixel for pixel (#540).

`render()` draws either through canvas_mojo's supersampled region, which
replays recorded drawing one output band at a time, or through the
two-step recipe that predates it: allocate a canvas `factor` times
larger, draw into it, box-downsample it back. #534 adopted the region on
the claim that the two are byte-identical.

That claim was checked once, by a benchmark harness in a scratch
directory that no longer exists. Nothing ran it again. It matters more
than it looks: `render()` currently picks between the paths per plot
(`_draws_bulk_markers`), so both are live, and when canvas_mojo's
recordable bulk-marker op lands and that gate is deleted, this
equivalence becomes the whole argument that the change was safe.

canvas_mojo tests the same property upstream, but only over
canvas-level scenes. Nothing there covers a dataviz render, where axis
frames, tick layout, legends and mark layers all meet the region. That
is what these tests cover.

Every test asserts on ink as well as on equality, because two blank
canvases are also identical and a render that drew nothing would
otherwise pass.
"""

from canvas.buffer import Canvas
from canvas.resize import downsample
from std.testing import TestSuite, assert_equal, assert_true

from _test_helpers import _assert_same_canvas

from dataviz import Theme, bar, contourf, line, pie, scatter
from dataviz.plot import (
    Plot,
    _render_into,
    _resolve_supersample,
    render,
)


def _two_step(plot: Plot) raises -> Canvas:
    """The pre-#534 recipe, spelled out so the test does not depend on
    `render()`'s choice of path.

    The half-pixel translate is what `downsample`'s box filter costs:
    averaging a `factor`-sized block shifts the sample point, and the
    shift is undone here rather than in the scale. `begin_supersampled`
    owns the same shift internally, which is why the two agree.

    Args:
        plot: The chart to render.

    Returns:
        The downsampled canvas.
    """
    var factor = _resolve_supersample(plot, "render")
    var scratch = Canvas(
        plot.width * factor, plot.height * factor, plot._theme.background
    )
    scratch.translate(Float64(factor - 1) / 2.0, Float64(factor - 1) / 2.0)
    scratch.scale(Float64(factor), Float64(factor))
    _render_into(scratch, plot, 0, 0, plot.width, plot.height)
    return downsample(scratch, factor)


def _ink(c: Canvas, plot: Plot) -> Int:
    """Pixels that differ from the theme background.

    Guards the whole file: `_assert_same_canvas` on two empty canvases
    passes, so every test needs to know something was drawn.

    Args:
        c: The rendered canvas.
        plot: The chart it came from, for its background color.

    Returns:
        The count of non-background pixels.
    """
    var bg = plot._theme.background
    var n = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r != bg.r or p.g != bg.g or p.b != bg.b or p.a != bg.a:
                n += 1
    return n


def _check(plot: Plot, label: String, want_factor: Int) raises:
    """Both paths agree on `plot`, and both drew something.

    Args:
        plot: The chart to render both ways.
        label: Message prefix on failure.
        want_factor: The supersample factor this mark must resolve to,
            asserted so a change to `_auto_supersample` cannot silently
            move a test off the path it was written for.
    """
    assert_equal(
        _resolve_supersample(plot, "render"),
        want_factor,
        label + ": supersample factor",
    )
    var viaregion = render(plot)
    var viatwostep = _two_step(plot)
    var drawn = _ink(viaregion, plot)
    assert_true(drawn > 50, label + ": drew only " + String(drawn) + " pixels")
    _assert_same_canvas(viaregion, viatwostep, label)


def _xs() -> List[Float64]:
    var x = List[Float64]()
    for i in range(12):
        x.append(Float64(i))
    return x^


def _ys() -> List[Float64]:
    var y = List[Float64]()
    for i in range(12):
        y.append(Float64((i * 7) % 11) + 1.0)
    return y^


def _labels() -> List[String]:
    var c = List[String]()
    for i in range(6):
        c.append("c" + String(i))
    return c^


def _grid() -> List[List[Float64]]:
    var z = List[List[Float64]]()
    for r in range(8):
        var row = List[Float64]()
        for c in range(8):
            row.append(Float64((r - 4) * (r - 4) + (c - 3) * (c - 3)))
        z.append(row^)
    return z^


def test_a_pie_agrees_between_the_two_render_paths() raises:
    # The best case for the region: an arc has no bulk entry point, so
    # every wedge records and replays per band.
    var v = List[Float64]()
    for i in range(6):
        v.append(Float64(i) + 1.0)
    _check(pie(_labels(), v, width=320, height=240), "pie", 3)


def test_a_scatter_agrees_between_the_two_render_paths() raises:
    # The case `render()` deliberately keeps on the two-step, because
    # `fill_circles_aa` cannot be recorded. Both paths must still agree:
    # the gate is a performance choice, not a correctness one, and when
    # it is deleted this is the test that says so.
    _check(scatter(_xs(), _ys(), width=320, height=240), "scatter", 3)


def test_a_line_agrees_between_the_two_render_paths() raises:
    # Factor 1, where the region is a no-op and the two-step still
    # allocates a same-size scratch and copies it back through
    # `downsample(c, 1)`. A separate code path from the factor-3 marks.
    _check(line(_xs(), _ys(), width=320, height=240), "line", 1)


def test_a_bar_agrees_between_the_two_render_paths() raises:
    var v = List[Float64]()
    for i in range(6):
        v.append(Float64((i * 3) % 7) + 2.0)
    _check(bar(_labels(), v, width=320, height=240), "bar", 1)


def test_a_filled_contour_agrees_between_the_two_render_paths() raises:
    # Many filled polygons rather than markers, and the second-best row
    # in the #534 measurements.
    _check(contourf(_grid(), width=320, height=240), "contourf", 3)


def test_an_effect_scatter_agrees_between_the_two_render_paths() raises:
    # Two translucent marker draws over the same centers, halo then
    # point, so the result depends on which was drawn first. That makes
    # this the case where a replay that reordered recorded ops would
    # show, which the marks painting disjoint areas above would not
    # catch. canvas_mojo pins the same property upstream at the canvas
    # level; this pins it through a whole dataviz render.
    var p = Plot().mark_effect_scatter().encode(x=_xs(), y=_ys()).size(320, 240)
    _check(p^, "effect scatter", 3)


def test_a_legend_and_axis_frame_are_inside_the_comparison() raises:
    # The region wraps the whole render, not just the mark layer, so the
    # axis frame, ticks, tick labels and legend go through it too. A
    # color channel turns the legend on; without it the marks above
    # would be most of what is compared.
    var p = (
        Plot().mark_point().encode(x=_xs(), y=_ys(), color=_ys()).size(360, 260)
    )
    _check(p^, "scatter with color legend", 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
