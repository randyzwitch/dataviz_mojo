"""Rendering invariants that hold across marks: the raster and SVG backends lay out
the same, the two render paths agree, every mark leaves ink, and marks stay
inside the plot rect.

One module rather than 4: every test module pays the same dependency
compilation, so the suite is organized by family (#605).
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.resize import downsample
from canvas.text.font_cache import FontCache
from canvas.vector.svg import SvgCanvas
from dataviz.core.colors import CRIMSON, WHITE
from dataviz.core.mark import Mark
from dataviz.core.theme import Theme
from dataviz.core.validate import _step_setter_name
from dataviz.layout import GridCell, _render_grid_tight, render_grid, save_grid
from dataviz.facets import _render_facets_tight, render_facets, save_facets
from dataviz.layers import _render_layers_tight, save_layers
from dataviz.plot import Plot
from dataviz.rendering import (
    _all_at_dpi,
    _at_dpi,
    _render_generic,
    _render_into,
    _resolve_supersample,
    render_tight,
    render_tight_pdf,
    render_tight_svg,
)
from dataviz import (
    area,
    line,
    render,
    render_layers,
    render_pdf,
    render_svg,
    save,
    scatter,
    Theme,
    arc_diagram,
    bar,
    barbs,
    beeswarm,
    box,
    boxenplot,
    bullet,
    bump,
    calendar_heatmap,
    candlestick,
    chord,
    contour,
    contourf,
    corrplot,
    ecdf,
    effect_scatter,
    eventplot,
    funnel,
    gantt,
    gauge,
    graph,
    grouped_bar,
    heatmap,
    hexbin,
    hist2d,
    histogram,
    imshow,
    kdeplot,
    lollipop,
    marimekko,
    nightingale,
    parallel,
    pcolormesh,
    pie,
    pointplot,
    polar,
    polarbar,
    population_pyramid,
    punchcard,
    quiver,
    radar,
    radialbar,
    ridgeline,
    rugplot,
    sankey,
    single_axis,
    span_chart,
    stacked_bar,
    streamgraph,
    streamplot,
    sunburst,
    tree,
    treemap,
    tricontour,
    tricontourf,
    tripcolor,
    triplot,
    violin,
    waterfall,
)
from _mark_registry import (
    _H,
    _W,
    _box_values,
    _cats,
    _edge_from,
    _edge_to,
    _edge_vals,
    _hier_vals,
    _ids,
    _nested,
    _parents,
    _representative_plot,
    _vals,
)
from _test_helpers import _assert_same_canvas


# ==== from test_backend_equivalence.mojo ====
# Raster/SVG layout equivalence, one sweep over every mark.
#
# Both backends go through the same `_render_generic[T: DrawTarget]`, but
# each mark's own tests exercise the two independently, so a divergence
# between them is caught only where a mark happens to have a test on the
# affected side. This module asserts the thing that must hold for every
# mark: laying the same `Plot` out on a `Canvas` and on an `SvgCanvas`
# produces the same plot rect and the same text requests.
#
# It compares *layout*, not pixels -- the two backends draw differently by
# design, and a bitmap has no `<text>` element to compare against. What
# they must agree on is where the mark decided things go, which is exactly
# what `_RenderResult` carries.
#
# `_representative_plot` is a registry: one minimal, valid `Plot` per
# `Mark`. The sweep walks `Mark(0)` through `Mark(Mark.COUNT - 1)`, so a
# mark added without an entry here raises rather than quietly going
# untested.
#
# `Mark.name()` is tested here for the same reason and off the
# same range: it is the other per-mark table that a new mark has to be
# added to, and the failure mode is identical -- a missing entry is
# invisible until an error message names the wrong mark. Neither needs a
# render, so they cost nothing in this SVG-only module.


# The per-mark registry lives in _mark_registry.mojo, shared with the
# output-digest sweep (#570): two copies of a table with one entry per
# mark is how one of them ends up missing a mark.


def _assert_same_layout(mark_value: Int, plot: Plot) raises -> Int:
    """Lay `plot` out on both backends and require the results to match.

    Also checks the comparison isn't vacuous: a mark that laid out into
    an empty rect would pass a field-by-field compare while proving
    nothing, so the rect is required to have positive area. The returned
    text-request count lets the sweep make the same check across all
    marks at once.

    Args:
        mark_value: The mark's numeric value, for failure messages.
        plot: The plot to lay out.

    Returns:
        How many text requests the layout produced.
    """
    var label = " (mark value " + String(mark_value) + ")"

    # A fresh cache per backend, so neither starts from the other's
    # warmed state -- what is being compared is the layout the mark
    # decided, not the order the two runs happened in.
    var raster_cache = FontCache()
    var vector_cache = FontCache()
    var canvas = Canvas(_W, _H, WHITE)
    var svg = SvgCanvas(_W, _H)
    var raster = _render_generic(canvas, plot, 0, 0, _W, _H, cache=raster_cache)
    var vector = _render_generic(svg, plot, 0, 0, _W, _H, cache=vector_cache)

    assert_equal(raster.px0, vector.px0, "plot rect px0 differs" + label)
    assert_equal(raster.py0, vector.py0, "plot rect py0 differs" + label)
    assert_equal(raster.px1, vector.px1, "plot rect px1 differs" + label)
    assert_equal(raster.py1, vector.py1, "plot rect py1 differs" + label)

    assert_equal(
        len(raster.text_requests),
        len(vector.text_requests),
        "text request count differs" + label,
    )
    for i in range(len(raster.text_requests)):
        ref a = raster.text_requests[i]
        ref b = vector.text_requests[i]
        var at = label + ", text request " + String(i) + " '" + a.text + "'"
        assert_equal(a.text, b.text, "text differs" + at)
        assert_equal(a.x, b.x, "x differs" + at)
        assert_equal(a.y, b.y, "y differs" + at)
        assert_equal(a.size, b.size, "size differs" + at)
        assert_equal(a.family, b.family, "family differs" + at)
        assert_equal(a.bold, b.bold, "bold differs" + at)
        assert_equal(a.rotation, b.rotation, "rotation differs" + at)
        assert_true(a.align == b.align, "align differs" + at)
        assert_equal(a.color.r, b.color.r, "color differs" + at)
        assert_equal(a.color.g, b.color.g, "color differs" + at)
        assert_equal(a.color.b, b.color.b, "color differs" + at)

    assert_true(
        raster.px1 > raster.px0 and raster.py1 > raster.py0,
        "laid out into an empty plot rect, so the comparison proved nothing"
        + label,
    )
    return len(raster.text_requests)


def test_every_mark_lays_out_identically_on_both_backends() raises:
    """The sweep: every mark, both backends, same plot rect and same text
    requests.

    Walks `Mark(0)` through `Mark(Mark.COUNT - 1)` rather than a list
    written here, so adding a mark without a representative dataset
    raises out of `_representative_plot` instead of silently reducing
    coverage.
    """
    var total_text_requests = 0
    for value in range(Mark.COUNT):
        var plot = _representative_plot(Mark(value))
        total_text_requests += _assert_same_layout(value, plot)

    # If every mark somehow produced no text at all, each comparison
    # above would still pass while checking nothing about the half of
    # _RenderResult that carries the most detail.
    assert_true(
        total_text_requests > 0,
        "no mark produced any text request -- the sweep would be vacuous",
    )


def test_every_mark_value_has_a_representative_plot() raises:
    """`_representative_plot` covers the whole `Mark` range. Separate from
    the sweep above so a missing entry reports as "nothing to test this
    mark with" rather than as a layout mismatch.
    """
    for value in range(Mark.COUNT):
        var plot = _representative_plot(Mark(value))
        assert_true(
            plot._mark == Mark(value),
            "representative plot for mark value "
            + String(value)
            + " actually uses a different mark",
        )


def test_backends_agree_when_a_legend_widens_the_plot_rect() raises:
    """A legend is reserved out of the plot rect before either backend
    draws, so both must land on the same narrowed rect. Grouped bar with
    long series names is the case where the reserve is dynamic rather
    than fixed.
    """
    var cats = _cats()
    var series: List[String] = [
        "a series with a rather long name",
        "another long series name",
    ]
    var plot = grouped_bar(cats, series, _nested(), width=_W, height=_H)
    _ = _assert_same_layout(Mark.GROUPED_BAR._value, plot)


def test_backends_agree_with_titles_and_rotated_axis_labels() raises:
    """Labels and rotated categorical ticks are pure `_TextRequest`
    output, so they are exactly what this comparison is for.
    """
    var cats: List[String] = [
        "Category Number One",
        "Category Number Two",
        "Category Number Three",
    ]
    var vals = _vals()
    var plot = bar(
        cats,
        vals,
        title="A title",
        subtitle="and a subtitle",
        x_title="x",
        y_title="y",
        width=_W,
        height=_H,
    )
    _ = _assert_same_layout(Mark.BAR._value, plot)


def test_mark_name_spells_the_constant() raises:
    """`Mark.name()` returns the qualified constant name a caller would
    type.

    A spot check rather than all of them, because the sweep below is
    what covers the rest; these are the ones whose spelling a chain of
    branches is most likely to get wrong -- an underscore name, two
    names sharing a prefix (`CONTOUR`/`CONTOURF`,
    `TRICONTOUR`/`TRICONTOURF`), and the first and last constants.
    """
    assert_equal(Mark.POINT.name(), "Mark.POINT")
    assert_equal(Mark.GROUPED_BAR.name(), "Mark.GROUPED_BAR")
    assert_equal(Mark.CONTOUR.name(), "Mark.CONTOUR")
    assert_equal(Mark.CONTOURF.name(), "Mark.CONTOURF")
    assert_equal(Mark.TRICONTOUR.name(), "Mark.TRICONTOUR")
    assert_equal(Mark.TRICONTOURF.name(), "Mark.TRICONTOURF")
    assert_equal(Mark.TRIPCOLOR.name(), "Mark.TRIPCOLOR")
    assert_equal(Mark.ECDF.name(), "Mark.ECDF")
    assert_equal(Mark.EVENTPLOT.name(), "Mark.EVENTPLOT")


def test_every_mark_has_its_own_name() raises:
    """Every value in `[0, Mark.COUNT)` names itself, and no two share a
    name.

    This is the assertion that makes a chain this long safe to extend.
    Two things go wrong in one and neither is visible by reading it:
    a mark added without a branch falls through to the `Mark(<n>)`
    fallback, and a branch copy-pasted from its neighbor returns the
    neighbor's name -- at which point an error message confidently
    names the wrong mark, which is worse than the "a different mark"
    it replaced.

    Checking against the fallback's exact spelling is what catches the
    first case; the O(n^2) distinctness scan is what catches the second.
    A test that only asserted `name()` is non-empty, or only that it
    starts with "Mark.", would pass through both.
    """
    var names = List[String]()
    for value in range(Mark.COUNT):
        var name = Mark(value).name()
        assert_true(
            name != "Mark(" + String(value) + ")",
            (
                "mark value "
                + String(value)
                + " has no branch in Mark.name() -- it fell through to the"
                " unknown-value fallback"
            ),
        )
        names.append(name)

    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            assert_true(
                names[i] != names[j],
                (
                    "mark values "
                    + String(i)
                    + " and "
                    + String(j)
                    + " both name themselves "
                    + names[i]
                ),
            )


def test_mark_name_falls_back_for_an_unknown_value() raises:
    """A value past the last constant has no name to give, so it reports
    the value instead of guessing.

    Paired with the sweep above this pins the branch list to exactly
    `Mark.COUNT` entries: that test fails if a value below `COUNT` hits
    the fallback, this one fails if `COUNT` itself does not.

    **The pair only works while `name()` is complete, and once it was
    not.** `Mark.DENDROGRAM` arrived as `Self(62)` with `COUNT` left at
    62 and no `name()` branch of its own. This test asked for
    `Mark(62).name()` to be the fallback, and it was -- not because 62
    was past the end, but because the branch was missing. The two
    defects cancelled and both tests passed, while every sweep over
    `range(Mark.COUNT)` stopped one short of the new mark: the output
    digest never fingerprinted it, `_mark_registry`'s "raises for a
    mark with no entry" never fired for it, and the missing entry went
    unnoticed for as long as that held.

    A third test used to guard `COUNT` directly and named
    `Mark.STREAMPLOT` as the newest mark by hand, so it rotted the
    moment a newer one arrived and passed against the wrong constant.
    It was removed rather than re-pinned to `DENDROGRAM`, which would
    only restart the same clock.

    So when adding a mark: bump `COUNT`, add the `name()` branch, and
    add the `_mark_registry` entry. Two of the three are checked here;
    the digest gaining a line for the new mark is what shows the third
    landed.
    """
    assert_equal(Mark(Mark.COUNT).name(), "Mark(" + String(Mark.COUNT) + ")")
    assert_equal(Mark(-1).name(), "Mark(-1)")


def test_step_setter_name_is_derived_from_the_mark() raises:
    """`_check_step_smoothing`'s message names the builder mechanically
    , not from a chain of `==` that listed three marks.

        `Mark.GROUPED_BAR` is the discriminating case: it never had a branch
        in the old chain, so that returned `Plot.mark_line(step=...)` for
        it. It also has an underscore, which a derivation that lowercased
        the whole `Mark.GROUPED_BAR` string without stripping the prefix
        would render as `Plot.mark_mark.grouped_bar(step=...)`.

        The three marks the old chain did list are asserted too, since the
        point of deriving is that the messages callers already see do not
        change; tests/test_marks_basic.mojo and
        tests/test_marks_distribution.mojo assert those same strings out of
        a real render.
    """
    assert_equal(_step_setter_name(Mark.LINE), "Plot.mark_line(step=...)")
    assert_equal(_step_setter_name(Mark.AREA), "Plot.mark_area(step=...)")
    assert_equal(
        _step_setter_name(Mark.STREAMGRAPH),
        "Plot.mark_streamgraph(step=...)",
    )
    assert_equal(
        _step_setter_name(Mark.GROUPED_BAR),
        "Plot.mark_grouped_bar(step=...)",
    )
    assert_equal(
        _step_setter_name(Mark(Mark.COUNT)), "Plot.mark_line(step=...)"
    )


# ==== from test_render_path_equivalence.mojo ====
# The two raster render paths must agree, pixel for pixel (#540).
#
# `render()` draws either through canvas_mojo's supersampled region, which
# replays recorded drawing one output band at a time, or through the
# two-step recipe that predates it: allocate a canvas `factor` times
# larger, draw into it, box-downsample it back. #534 adopted the region on
# the claim that the two are byte-identical.
#
# That claim was checked once, by a benchmark harness in a scratch
# directory that no longer exists. Nothing ran it again. It matters more
# than it looks: `render()` currently picks between the paths per plot
# (`_draws_bulk_markers`), so both are live, and when canvas_mojo's
# recordable bulk-marker op lands and that gate is deleted, this
# equivalence becomes the whole argument that the change was safe.
#
# canvas_mojo tests the same property upstream, but only over
# canvas-level scenes. Nothing there covers a dataviz render, where axis
# frames, tick layout, legends and mark layers all meet the region. That
# is what these tests cover.
#
# Every test asserts on ink as well as on equality, because two blank
# canvases are also identical and a render that drew nothing would
# otherwise pass.


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
    var factor = _resolve_supersample(plot._mark, plot._settings.theme, "render")
    var scratch = Canvas(
        plot.width * factor,
        plot.height * factor,
        plot._settings.theme.background,
    )
    scratch.translate(Float64(factor - 1) / 2.0, Float64(factor - 1) / 2.0)
    scratch.scale(Float64(factor), Float64(factor))
    _ = _render_into(scratch, plot, 0, 0, plot.width, plot.height)
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
    var bg = plot._settings.theme.background
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
        _resolve_supersample(plot._mark, plot._settings.theme, "render"),
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


# ==== from test_mark_ink.mojo ====
# Every mark actually puts ink on a raster canvas.
#
# The assertion looks trivial and is not. canvas's `begin_batch()` /
# `end_batch()` records shapes and draws them at `end_batch`, and reads
# are *not* ordered against a pending batch. `render()` ends with
#
#     _render_into(scratch, plot, ...)
#     return downsample(scratch, factor)
#
# and `downsample` is a read, so a `begin_batch()` that never closes --
# an unbalanced pair, or a loop with an early `return` between them --
# produces a chart with the mark silently missing. No error, and only on
# the raster backend, since the vector ones make both calls no-ops.
#
# Counting *any* non-background pixel would not catch that: axes,
# gridlines and text are drawn outside a mark's loop and would still be
# there. So the theme below paints all of that in the background color,
# leaving the mark's own geometry as the only thing that can differ from
# the background.
#
# Walks `Mark(0)` through `Mark(Mark.COUNT - 1)` off the same registry the
# backend-equivalence sweep uses, so a new mark is covered without being
# added here.


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
        plot._settings.theme = _chrome_free_theme()
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


# ==== from test_plot_clipping.mojo ====
# Tests for plot-area clipping (#369).
#
# With an axis domain narrower than the data, marks used to paint over the
# axis labels and off the canvas: nothing clipped, because the mark layers
# draw through `T: DrawTarget` and clipping was not on that trait until
# canvas v0.32.0. The measure here is the one that found the bug --- count
# pixels of the mark color outside the plot rect --- so a regression reads
# the same way the original report did.


# 400x300 with gridlines off: the plot rect is x:[60,380], y:[20,250].
comptime _X0 = 60
comptime _X1 = 380
comptime _Y0 = 20
comptime _Y1 = 250


def _theme() -> Theme:
    return Theme(show_gridlines=False, mark_color=CRIMSON)


def _outside(c: Canvas) raises -> Int:
    var n = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == CRIMSON.r and p.g == CRIMSON.g and p.b == CRIMSON.b:
                if x < _X0 or x > _X1 or y < _Y0 or y > _Y1:
                    n += 1
    return n


def _inside(c: Canvas) raises -> Int:
    var n = 0
    for y in range(_Y0, _Y1 + 1):
        for x in range(_X0, _X1 + 1):
            var p = c.get_pixel(x, y)
            if p.r == CRIMSON.r and p.g == CRIMSON.g and p.b == CRIMSON.b:
                n += 1
    return n


def _ramp() -> Tuple[List[Float64], List[Float64]]:
    var xs = List[Float64]()
    var ys = List[Float64]()
    for i in range(40):
        xs.append(Float64(i))
        ys.append(Float64((i * 13) % 20))
    return (xs^, ys^)


def test_a_pinned_x_domain_keeps_every_mark_inside_the_plot_rect() raises:
    # The reproduction from #369. Before the fix: 67 stray pixels for the
    # scatter and 268 for the line, painted across the y-axis labels and
    # off both edges of the canvas.
    var d = _ramp()
    var s = render(
        scatter(
            d[0], d[1], theme=_theme(), width=400, height=300
        ).scale_x_domain(15.0, 25.0)
    )
    assert_equal(_outside(s), 0, "no scatter marker escapes the plot rect")
    assert_true(_inside(s) > 100, "and the markers inside are still drawn")

    var l = render(
        line(d[0], d[1], theme=_theme(), width=400, height=300).scale_x_domain(
            15.0, 25.0
        )
    )
    assert_equal(_outside(l), 0, "no line segment escapes the plot rect")
    assert_true(_inside(l) > 300, "and the line inside is still drawn")


def test_a_pinned_y_domain_clips_too() raises:
    var d = _ramp()
    var s = render(
        scatter(
            d[0], d[1], theme=_theme(), width=400, height=300
        ).scale_y_domain(5.0, 12.0)
    )
    assert_equal(_outside(s), 0, "clipping is not an x-axis-only fix")
    assert_true(_inside(s) > 100, "the visible markers survive")


def test_an_area_and_a_histogram_are_clipped_as_well() raises:
    var d = _ramp()
    var a = render(
        area(d[0], d[1], theme=_theme(), width=400, height=300).scale_x_domain(
            15.0, 25.0
        )
    )
    assert_equal(_outside(a), 0, "the area fill stops at the plot rect")
    assert_true(_inside(a) > 500, "and still fills inside it")

    var values = List[Float64]()
    for i in range(60):
        values.append(Float64(i % 20))
    var h = render(
        histogram(
            values, bins=8, theme=_theme(), width=400, height=300
        ).scale_x_domain(5.0, 12.0)
    )
    assert_equal(_outside(h), 0, "no bar escapes the plot rect")
    assert_true(_inside(h) > 500, "and the bars inside are drawn")


def test_a_layered_chart_is_clipped_by_the_same_code() raises:
    # `render_layers()` calls the same layer functions against a frame it
    # built, which is why the clip is pushed from the scales inside the
    # layer rather than from a frame outside it.
    var d = _ramp()
    var plots: List[Plot] = [
        line(d[0], d[1], theme=_theme(), width=400, height=300).scale_x_domain(
            15.0, 25.0
        ),
        scatter(
            d[0], d[1], theme=_theme(), width=400, height=300
        ).scale_x_domain(15.0, 25.0),
    ]
    var c = render_layers(plots)
    assert_equal(_outside(c), 0, "an overlay clips its layers too")
    assert_true(_inside(c) > 300, "and both layers still draw")


def test_the_axis_furniture_is_not_clipped_away() raises:
    # The clip covers the mark layer only. A tick label sits below the
    # plot rect and must survive, or the fix would have traded one bug
    # for a worse one.
    var d = _ramp()
    var t = Theme(show_gridlines=False)
    var c = render(
        line(d[0], d[1], theme=t, width=400, height=300).scale_x_domain(
            15.0, 25.0
        )
    )
    # Counted as "not the page color" rather than as an exact text
    # color: the glyphs are antialiased, so only a handful of pixels
    # ever land on `Theme.text_color` exactly.
    var label_ink = 0
    for y in range(_Y1 + 2, c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if not (p.r == 255 and p.g == 255 and p.b == 255):
                label_ink += 1
    assert_true(
        label_ink > 100,
        "the x tick labels are still drawn -- got " + String(label_ink),
    )


def test_an_unpinned_chart_is_unchanged() raises:
    # Nothing moves for the common case: without a domain override the
    # data already fits, so the clip is a no-op.
    var d = _ramp()
    var c = render(scatter(d[0], d[1], theme=_theme(), width=400, height=300))
    assert_equal(_outside(c), 0)
    assert_true(_inside(c) > 100, "the whole scatter is inside anyway")


# ==== PDF export and the physical-size contract (#372) ====
# One layout unit is one point, 1/72 inch: that is the whole contract,
# and everything below is a consequence of it.


def _pdf_plot() raises -> Plot:
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 4.0]
    return scatter(
        x, y, theme=Theme(show_legend=False), title="Export"
    ).size_inches(6.5, 4.0)


def _bytes_have(data: List[UInt8], needle: String) -> Bool:
    """Whether the ASCII `needle` appears in `data`."""
    var n = needle.as_bytes()
    if len(n) == 0 or len(data) < len(n):
        return False
    for i in range(len(data) - len(n) + 1):
        var hit = True
        for j in range(len(n)):
            if data[i + j] != n[j]:
                hit = False
                break
        if hit:
            return True
    return False


def _file_bytes(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var data = f.read_bytes()
    f.close()
    return data^


def test_a_pdf_page_is_the_figure_in_points() raises:
    # 6.5 by 4 inches at 72 points to the inch.
    var p = _pdf_plot()
    assert_equal(p.width, 468, "6.5 inches is 468 points")
    assert_equal(p.height, 288, "4 inches is 288 points")
    var doc = render_pdf(p)
    assert_equal(doc.width, 468, "and the page is the figure")
    assert_equal(doc.height, 288)
    var out = doc.to_bytes()
    assert_true(
        _bytes_have(out, "/MediaBox [0 0 468 288]"),
        "the document says so too",
    )


def test_size_inches_and_size_mm_meet_on_the_same_page() raises:
    # 6.5 inches is 165.1 mm; both have to land on the same points or
    # one of the two conversions is wrong.
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [1.0, 2.0]
    var inches = scatter(x, y).size_inches(6.5, 4.0)
    var mm = scatter(x, y).size_mm(165.1, 101.6)
    assert_equal(inches.width, mm.width)
    assert_equal(inches.height, mm.height)


def test_a_pdf_carries_its_labels_as_embedded_text() raises:
    # The reason to write a PDF rather than place a PNG: the title is
    # text in an embedded font subset, so it is selectable, searchable
    # and sharp at any zoom, not a picture of itself.
    var doc = render_pdf(_pdf_plot())
    var out = doc.to_bytes()
    assert_true(_bytes_have(out, "/FontFile"), "a font is embedded")
    assert_true(_bytes_have(out, "/ToUnicode"), "with a character map")


def test_cjk_title_exports_with_collection_font() raises:
    # Noto Sans CJK is a .ttc collection on Linux. The fallback face used
    # to be discovered but then rejected by the font parser (#754).
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [1.0, 2.0]
    var p = line(x, y).labels(title="東京")

    var png_path = "/tmp/dataviz_test_cjk_title.png"
    save(p, png_path)
    var png = _file_bytes(png_path)
    assert_equal(Int(png[1]), 80, "CJK title PNG header")

    var pdf_path = "/tmp/dataviz_test_cjk_title.pdf"
    save(p, pdf_path)
    var pdf = _file_bytes(pdf_path)
    assert_equal(Int(pdf[0]), 37, "CJK title PDF header")
    assert_true(_bytes_have(pdf, "/ToUnicode"), "CJK text has a map")


def test_saving_a_pdf_writes_a_pdf() raises:
    var path = "/tmp/dataviz_test_export.pdf"
    save(_pdf_plot(), path)
    var data = _file_bytes(path)
    assert_true(len(data) > 0, "the file has content")
    assert_equal(Int(data[0]), 37, "starts with %")
    assert_equal(Int(data[1]), 80, "P")
    assert_equal(Int(data[2]), 68, "D")
    assert_equal(Int(data[3]), 70, "F")


def _ink_fraction(c: Canvas, theme: Theme) -> Float64:
    var bg = theme.background
    var n = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if not (p.r == bg.r and p.g == bg.g and p.b == bg.b):
                n += 1
    return Float64(n) / Float64(c.width * c.height)


def test_dpi_multiplies_the_pixels_and_keeps_the_figure() raises:
    # The claim a resolution has to keep: the same figure, finer. If
    # only the canvas grew, the furniture would stay the size it was and
    # cover a far smaller share of it.
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 4.0]
    var t = Theme(show_legend=False)
    var base = scatter(x, y, theme=t, title="Export").size(200, 150)
    var low = render(base)
    var high = render(_at_dpi(base, 288.0))
    assert_equal(high.width, 800, "four times the pixels across")
    assert_equal(high.height, 600)
    var a = _ink_fraction(low, t)
    var b = _ink_fraction(high, t)
    assert_true(
        abs(a - b) < 0.02,
        "the same share of the page is ink: "
        + String(a)
        + " against "
        + String(b),
    )


def test_the_default_resolution_leaves_a_raster_where_it_was() raises:
    # Every existing call goes through `_at_dpi` now, so the identity
    # case is worth pinning: one pixel per point, nothing rescaled.
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [1.0, 3.0, 2.0]
    var p = scatter(x, y, theme=Theme(show_legend=False)).size(200, 150)
    var plain = render(p)
    var same = render(_at_dpi(p, 72.0))
    assert_equal(same.width, plain.width)
    assert_equal(same.height, plain.height)
    for yy in range(0, plain.height, 7):
        for xx in range(0, plain.width, 7):
            var q = plain.get_pixel(xx, yy)
            var r = same.get_pixel(xx, yy)
            assert_true(
                q.r == r.r and q.g == r.g and q.b == r.b,
                "pixel (" + String(xx) + ", " + String(yy) + ") moved",
            )


def test_a_resolution_has_to_be_positive() raises:
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [1.0, 2.0]
    with assert_raises(contains="dpi must be positive"):
        save(scatter(x, y), "/tmp/dataviz_test_bad_dpi.png", dpi=0.0)


def test_a_transparent_background_reaches_the_file() raises:
    # Part of the export contract, and already supported by the raster
    # backend: a zero-alpha background leaves the page clear rather than
    # white, and the writer keeps the alpha channel.
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [1.0, 3.0, 2.0]
    var t = Theme(background=Color(255, 255, 255, 0), show_legend=False)
    var c = render(scatter(x, y, theme=t).size(200, 150))
    assert_equal(Int(c.get_pixel(2, 2).a), 0, "the corner is clear")
    var path = "/tmp/dataviz_test_clear.png"
    save(scatter(x, y, theme=t).size(200, 150), path)
    var data = _file_bytes(path)
    # IHDR's color type byte: 6 is truecolor with alpha.
    assert_equal(Int(data[25]), 6, "the PNG keeps an alpha channel")


def test_every_multi_plot_save_writes_a_real_pdf() raises:
    # Each of the three had an `else: write_bmp` fallthrough, so a .pdf
    # path would have written BMP bytes under a PDF name. They go
    # through their own PDF renders now, and this is what says so.
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 4.0]
    var t = Theme(show_legend=False)
    var plots = List[Plot]()
    plots.append(scatter(x, y, theme=t).size(300, 200))
    plots.append(line(x, y, theme=t).size(300, 200))

    var facets = "/tmp/dataviz_test_facets.pdf"
    save_facets(plots, 2, facets)
    var a = _file_bytes(facets)
    assert_equal(Int(a[0]), 37, "save_facets wrote a PDF")
    assert_true(_bytes_have(a, "/MediaBox [0 0 600 200]"), "at 2x300 points")

    var layers = "/tmp/dataviz_test_layers.pdf"
    save_layers(plots, layers)
    var b = _file_bytes(layers)
    assert_equal(Int(b[0]), 37, "save_layers wrote a PDF")
    assert_true(_bytes_have(b, "/MediaBox [0 0 300 200]"), "at one plot size")

    var cells = List[GridCell]()
    cells.append(GridCell(0, 0))
    cells.append(GridCell(0, 1))
    var grid = "/tmp/dataviz_test_grid_export.pdf"
    save_grid(plots, cells, 640, 300, grid)
    var c = _file_bytes(grid)
    assert_equal(Int(c[0]), 37, "save_grid wrote a PDF")
    assert_true(
        _bytes_have(c, "/MediaBox [0 0 640 300]"), "at the size it was given"
    )


# ==== a transparent background is the same promise on every backend (#372) ====
# `test_a_transparent_background_reaches_the_file` above pins the raster
# half: the corner pixel's alpha, and the PNG keeping an alpha channel.
# Its comment says "already supported by the raster backend", which was
# the honest scope at the time.
#
# The vector backends were the gap. Both already honor it -- SVG emits
# `fill-opacity="0.000"` on the figure ground and PDF adds an ExtGState
# carrying `/ca` -- but nothing said so, and each reaches transparency
# by a different mechanism, so any one of the three could regress
# without the other two noticing. #372 wants the export contract to
# hold across formats, which means all three are checked or the promise
# is only about PNG.


def _clear_theme() -> Theme:
    """A theme whose background is fully transparent."""
    return Theme(background=Color(255, 255, 255, 0))


def _tiny_plot(theme: Theme) raises -> Plot:
    """A small line chart under `theme`, enough to have a background."""
    var xs: List[Float64] = [1.0, 2.0, 3.0]
    var ys: List[Float64] = [1.0, 4.0, 2.0]
    return line(xs, ys, theme=theme).size(200, 150)


def _pdf_contains(data: List[UInt8], needle: String) -> Bool:
    """Whether the uncompressed PDF bytes contain `needle`."""
    var n = needle.as_bytes()
    for i in range(len(data) - len(n) + 1):
        var hit = True
        for j in range(len(n)):
            if data[i + j] != n[j]:
                hit = False
                break
        if hit:
            return True
    return False


def test_a_transparent_background_reaches_the_raster_backend() raises:
    var c = render(_tiny_plot(_clear_theme()))
    var corner = c.get_pixel(1, 1)
    assert_equal(Int(corner.a), 0, "the raster corner is not transparent")


def test_a_transparent_background_reaches_the_svg_backend() raises:
    # The figure ground is still emitted as a rect; what makes it
    # transparent is its fill-opacity, so that is what is asserted
    # rather than the rect's absence.
    var svg = render_svg(_tiny_plot(_clear_theme())).to_string()
    assert_true(
        'fill-opacity="0.000"' in svg,
        "the SVG background carries no zero fill-opacity",
    )


def test_a_transparent_background_reaches_the_pdf_backend() raises:
    # PDF has no per-fill alpha channel: transparency is a graphics
    # state, so an ExtGState with /ca is what carrying it looks like.
    var pdf = render_pdf(_tiny_plot(_clear_theme()))
    var bytes = pdf.to_bytes(compress=False)
    assert_true(
        _pdf_contains(bytes, "/ca"),
        "the PDF carries no alpha graphics state",
    )
    assert_true(
        _pdf_contains(bytes, "ExtGState"),
        "the PDF carries no ExtGState",
    )


def test_an_opaque_background_costs_no_alpha_machinery() raises:
    # The other half of the contract, and what keeps the test above
    # honest: if a PDF always carried an ExtGState, finding one would
    # say nothing about transparency.
    var opaque = Theme(background=Color(255, 255, 255, 255))
    var pdf = render_pdf(_tiny_plot(opaque))
    var bytes = pdf.to_bytes(compress=False)
    assert_true(
        not _pdf_contains(bytes, "/ca"),
        "an opaque figure still emitted an alpha graphics state",
    )


# ==== tight bounds: crop a figure to its ink (#372) ====
# The last item of #372, and the one that needed an upstream primitive:
# cropping needs the ink's extent, which a raster canvas can be scanned
# for and an SvgCanvas or PdfCanvas cannot. canvas_mojo#460 added
# `BoundsTarget`, a DrawTarget that paints nothing and keeps the union
# of what it was asked to draw.
#
# The figure is laid out at its full size and then cropped, never laid
# out smaller: margins, tick spacing and legend width all derive from
# the rect, so a smaller layout would move the ink and the crop would
# chase it.


def _roomy_plot() raises -> Plot:
    """A small chart on a deliberately oversized figure, so there is
    whitespace for a crop to remove."""
    var xs: List[Float64] = [1.0, 2.0, 3.0]
    var ys: List[Float64] = [1.0, 4.0, 2.0]
    return line(xs, ys).size(600, 450)


def _ink_box_by_scanning(
    c: Canvas, bg: Color
) raises -> Tuple[Int, Int, Int, Int]:
    """The box around every pixel that is not the background, found by
    scanning. The independent answer a raster canvas can give, which is
    what `BoundsTarget`'s answer is checked against."""
    var min_x = c.width
    var min_y = c.height
    var max_x = -1
    var max_y = -1
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r != bg.r or p.g != bg.g or p.b != bg.b:
                if x < min_x:
                    min_x = x
                if x > max_x:
                    max_x = x
                if y < min_y:
                    min_y = y
                if y > max_y:
                    max_y = y
    return (min_x, min_y, max_x, max_y)


def test_a_tight_render_is_smaller_than_the_figure() raises:
    # The point of the feature: the whitespace a fixed size reserves is
    # gone.
    var full = render(_roomy_plot())
    var tight = render_tight(_roomy_plot())
    assert_true(
        tight.width < full.width and tight.height < full.height,
        (
            "the tight render did not shrink: "
            + String(tight.width)
            + "x"
            + String(tight.height)
            + " against "
            + String(full.width)
            + "x"
            + String(full.height)
        ),
    )


def test_the_measured_box_agrees_with_the_ink_it_crops_to() raises:
    # The check that the measured extent is the *ink* and not the
    # geometry someone assumed the ink would be. `BoundsTarget` answers
    # from the draw calls; this scans the pixels the same figure
    # actually produced and requires the two to agree.
    #
    # The box may be a pixel generous per side -- an anti-aliased edge
    # is partly covered, and a box that excluded a barely-inked pixel
    # would crop away ink -- so erring outward is the safe direction and
    # the only one allowed here.
    var plot = _roomy_plot()
    var bg = plot._settings.theme.background
    var full = render(plot)
    var scanned = _ink_box_by_scanning(full, bg)
    var tight = render_tight(_roomy_plot())

    var scanned_w = scanned[2] - scanned[0] + 1
    var scanned_h = scanned[3] - scanned[1] + 1
    assert_true(
        tight.width >= scanned_w and tight.height >= scanned_h,
        (
            "the crop is smaller than the ink it should cover: "
            + String(tight.width)
            + "x"
            + String(tight.height)
            + " against scanned "
            + String(scanned_w)
            + "x"
            + String(scanned_h)
        ),
    )
    assert_true(
        tight.width <= scanned_w + 2 and tight.height <= scanned_h + 2,
        (
            "the crop is more than a pixel per side larger than the ink: "
            + String(tight.width)
            + "x"
            + String(tight.height)
            + " against scanned "
            + String(scanned_w)
            + "x"
            + String(scanned_h)
        ),
    )


def test_a_tight_render_keeps_the_ink() raises:
    # Cropping must not shave the thing it cropped to. Every cropped
    # figure still has ink on it, and as much of it as before.
    var plot = _roomy_plot()
    var bg = plot._settings.theme.background
    var full = render(plot)
    var tight = render_tight(_roomy_plot())
    var full_ink = 0
    for y in range(full.height):
        for x in range(full.width):
            var p = full.get_pixel(x, y)
            if p.r != bg.r or p.g != bg.g or p.b != bg.b:
                full_ink += 1
    var tight_ink = 0
    for y in range(tight.height):
        for x in range(tight.width):
            var p = tight.get_pixel(x, y)
            if p.r != bg.r or p.g != bg.g or p.b != bg.b:
                tight_ink += 1
    assert_true(
        tight_ink >= full_ink,
        (
            "the crop lost ink: "
            + String(tight_ink)
            + " inked pixels against "
            + String(full_ink)
            + " before"
        ),
    )


def test_tight_cropping_reaches_the_vector_backends() raises:
    # The reason a measuring target was worth asking for: neither of
    # these has pixels to scan, so nothing else could have cropped them.
    var svg = render_tight_svg(_roomy_plot())
    assert_true(svg.width < 600, "the SVG did not crop")
    assert_true(svg.height < 450, "the SVG did not crop")
    var pdf = render_tight_pdf(_roomy_plot())
    assert_true(pdf.width < 600, "the PDF page did not crop")
    assert_true(pdf.height < 450, "the PDF page did not crop")


def test_all_three_backends_crop_to_the_same_box() raises:
    # One measurement, so a figure exported three ways is the same
    # figure at the same size rather than three near-misses.
    var raster = render_tight(_roomy_plot())
    var svg = render_tight_svg(_roomy_plot())
    var pdf = render_tight_pdf(_roomy_plot())
    assert_equal(svg.width, pdf.width, "SVG and PDF cropped differently")
    assert_equal(svg.height, pdf.height, "SVG and PDF cropped differently")
    # The raster figure is measured for a raster draw, which can differ
    # from the vector one where a mark draws differently for markup, so
    # this asks only that it is the same to within a pixel per side.
    assert_true(
        abs(raster.width - svg.width) <= 2
        and abs(raster.height - svg.height) <= 2,
        (
            "raster and vector crops disagree: "
            + String(raster.width)
            + "x"
            + String(raster.height)
            + " against "
            + String(svg.width)
            + "x"
            + String(svg.height)
        ),
    )


# ---------------------------------------------------------------
# save() format contract for rendered canvases (#696)


def _write_sentinel(path: String) raises:
    """Put a known byte sequence at `path` so a later read can say
    whether a refused save touched it."""
    var f = open(path, "w")
    f.write("SENTINEL")
    f.close()


def _still_sentinel(path: String) raises -> Bool:
    """Whether `path` still holds exactly what `_write_sentinel` put
    there -- that is, the refused save neither truncated nor rewrote
    it."""
    var f = open(path, "r")
    var text = f.read()
    f.close()
    return text == "SENTINEL"


def test_each_rendered_canvas_saves_to_its_own_format() raises:
    # The signature, not the extension: the bug this guards produced
    # files whose name and contents disagreed.
    var p = _tiny_plot(_clear_theme())
    var png = "/tmp/dataviz_test_contract.png"
    save(render(p), png)
    var a = _file_bytes(png)
    assert_equal(Int(a[1]), 80, "PNG's second byte is 'P'")

    var svg = "/tmp/dataviz_test_contract.svg"
    save(render_svg(p), svg)
    var b = _file_bytes(svg)
    assert_equal(Int(b[0]), 60, "SVG starts with '<'")

    var pdf = "/tmp/dataviz_test_contract.pdf"
    save(render_pdf(p), pdf)
    var c = _file_bytes(pdf)
    assert_equal(Int(c[0]), 37, "PDF starts with '%'")


def test_a_rendered_canvas_refuses_a_path_it_cannot_honor() raises:
    # save(canvas, "chart.pdf") wrote PNG bytes and save(svg, "chart.pdf")
    # wrote markup: each overload rejected only the extensions someone
    # had thought of, and the rest fell through to the default writer
    # (#696). The rejection happens before the file is opened, so a
    # refused path is left untouched rather than created and truncated.
    # Each destination is seeded first, so the assertion is that the
    # refused save left it exactly as it found it -- stronger than "no
    # file appeared", and independent of what an earlier run left in
    # /tmp.
    var p = _tiny_plot(_clear_theme())
    var raster_to_pdf = "/tmp/dataviz_test_refuse_a.pdf"
    _write_sentinel(raster_to_pdf)
    with assert_raises(contains="cannot write a .pdf"):
        save(render(p), raster_to_pdf)
    assert_true(_still_sentinel(raster_to_pdf), "and left the file alone")

    var svg_to_pdf = "/tmp/dataviz_test_refuse_b.pdf"
    _write_sentinel(svg_to_pdf)
    with assert_raises(contains="vector markup, not pixels"):
        save(render_svg(p), svg_to_pdf)
    assert_true(_still_sentinel(svg_to_pdf), "and left the file alone")

    var pdf_to_png = "/tmp/dataviz_test_refuse_c.png"
    _write_sentinel(pdf_to_png)
    with assert_raises(contains="cannot write a .png"):
        save(render_pdf(p), pdf_to_png)
    assert_true(_still_sentinel(pdf_to_png), "and left the file alone")

    var pdf_to_svg = "/tmp/dataviz_test_refuse_d.svg"
    _write_sentinel(pdf_to_svg)
    with assert_raises(contains="cannot write a .svg"):
        save(render_pdf(p), pdf_to_svg)
    assert_true(_still_sentinel(pdf_to_svg), "and left the file alone")


def test_a_path_with_no_extension_takes_the_canvas_default() raises:
    # An absent extension is the one case that still falls through to
    # the canvas's own writer, which is what keeps save(canvas, "out")
    # working. A dot inside a directory name is not an extension, so
    # that path takes the default too.
    var p = _tiny_plot(_clear_theme())
    var path = "/tmp/dataviz_test_contract_noext"
    save(render(p), path)
    var a = _file_bytes(path)
    assert_equal(Int(a[1]), 80, "still a PNG")


def test_an_unrecognized_extension_is_refused_rather_than_guessed() raises:
    # #696 listed the extensions each overload had to refuse, which left
    # every extension nobody had thought of falling through to the
    # default writer: save(plot, "chart.jpg") wrote SVG markup into a
    # file named .jpg and reported success, and .jpeg, .gif, .webp,
    # .tif, .eps and .html did the same (#755). A file that says .jpg
    # and holds SVG is worse than a failed save, because nothing
    # reports it. The test is now an allow-list, so this stays closed
    # for extensions nobody has thought of yet either.
    var p = _tiny_plot(_clear_theme())
    var unwritable: List[String] = [
        ".jpg",
        ".jpeg",
        ".gif",
        ".webp",
        ".tif",
        ".eps",
        ".html",
    ]
    for ext in unwritable:
        var path = "/tmp/dataviz_test_unknown_ext" + ext
        _write_sentinel(path)
        with assert_raises(contains="don't know how to write a " + ext):
            save(p, path)
        assert_true(_still_sentinel(path), "left " + ext + " alone")

    # The already-rendered canvases refuse the same way, through their
    # own allow-lists, and name the canvas rather than the package.
    var svg_path = "/tmp/dataviz_test_unknown_svg.jpg"
    _write_sentinel(svg_path)
    with assert_raises(contains="cannot write a .jpg"):
        save(render_svg(p), svg_path)
    assert_true(_still_sentinel(svg_path), "left the SvgCanvas path alone")

    var raster_path = "/tmp/dataviz_test_unknown_raster.webp"
    _write_sentinel(raster_path)
    with assert_raises(contains="cannot write a .webp"):
        save(render(p), raster_path)
    assert_true(_still_sentinel(raster_path), "left the Canvas path alone")

    var pdf_path = "/tmp/dataviz_test_unknown_pdf.gif"
    _write_sentinel(pdf_path)
    with assert_raises(contains="cannot write a .gif"):
        save(render_pdf(p), pdf_path)
    assert_true(_still_sentinel(pdf_path), "left the PdfCanvas path alone")


def test_the_four_writable_extensions_still_write() raises:
    # The other half of the allow-list: it must not have closed over a
    # format this package does produce. One assertion per writer, by
    # magic bytes rather than by the call not raising.
    var p = _tiny_plot(_clear_theme())

    save(p, "/tmp/dataviz_test_ok.png")
    assert_equal(
        Int(_file_bytes("/tmp/dataviz_test_ok.png")[1]), 80, "PNG magic"
    )
    save(p, "/tmp/dataviz_test_ok.bmp")
    assert_equal(
        Int(_file_bytes("/tmp/dataviz_test_ok.bmp")[0]), 66, "BMP magic"
    )
    save(p, "/tmp/dataviz_test_ok.svg")
    assert_true(
        _file_text("/tmp/dataviz_test_ok.svg").startswith("<svg"), "SVG markup"
    )
    # By bytes, not text: a PDF embeds a font subset, so reading the
    # whole file as a String fails on invalid UTF-8.
    save(p, "/tmp/dataviz_test_ok.pdf")
    var pdf_bytes = _file_bytes("/tmp/dataviz_test_ok.pdf")
    assert_equal(Int(pdf_bytes[0]), 37, "PDF header %")
    assert_equal(Int(pdf_bytes[1]), 80, "PDF header P")
    assert_equal(Int(pdf_bytes[2]), 68, "PDF header D")
    assert_equal(Int(pdf_bytes[3]), 70, "PDF header F")

    # Case does not matter, and neither does a dot earlier in the name.
    save(p, "/tmp/dataviz_test_ok.v2.PNG")
    assert_equal(
        Int(_file_bytes("/tmp/dataviz_test_ok.v2.PNG")[1]), 80, "PNG magic"
    )


# ---------------------------------------------------------------
# dpi and tight on the composite savers (#701)


def _png_dims(path: String) raises -> Tuple[Int, Int]:
    """A PNG's width and height from its IHDR chunk: big-endian at bytes
    16 and 20, right after the 8-byte signature and the chunk header."""
    var b = _file_bytes(path)
    var w = (
        (Int(b[16]) << 24) | (Int(b[17]) << 16) | (Int(b[18]) << 8) | Int(b[19])
    )
    var h = (
        (Int(b[20]) << 24) | (Int(b[21]) << 16) | (Int(b[22]) << 8) | Int(b[23])
    )
    return (w, h)


def _file_text(path: String) raises -> String:
    var f = open(path, "r")
    var s = f.read()
    f.close()
    return s^


def _svg_root(svg: String) -> String:
    """The opening `<svg ...>` tag, where the document's own size is."""
    return String(svg[byte = 0 : svg.find(">") + 1])


def _roomy_pair() raises -> List[Plot]:
    """Two small charts on oversized figures -- whitespace for a crop to
    remove -- with titles and axis titles, so a crop that shaved text
    would lose ink."""
    var xs: List[Float64] = [1.0, 2.0, 3.0]
    var ys: List[Float64] = [1.0, 4.0, 2.0]
    var out = List[Plot]()
    out.append(
        line(xs, ys, title="Left", x_title="x", y_title="y").size(400, 300)
    )
    out.append(
        line(xs, ys, title="Right", x_title="x", y_title="y").size(400, 300)
    )
    return out^


def _two_cells() -> List[GridCell]:
    var cells: List[GridCell] = [GridCell(0, 0), GridCell(0, 1)]
    return cells^


def _inked(c: Canvas, bg: Color) -> Int:
    var n = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r != bg.r or p.g != bg.g or p.b != bg.b:
                n += 1
    return n


def test_the_composite_savers_take_dpi_as_save_does() raises:
    # 144 dpi is two pixels per point: each saver's PNG doubles in both
    # directions, where the default of 72 leaves it at the figure size.
    var plots = _roomy_pair()
    save_layers(plots, "/tmp/dv701_l72.png")
    save_layers(plots, "/tmp/dv701_l144.png", dpi=144.0)
    assert_equal(_png_dims("/tmp/dv701_l72.png")[0], 400)
    assert_equal(_png_dims("/tmp/dv701_l144.png")[0], 800)
    assert_equal(_png_dims("/tmp/dv701_l144.png")[1], 600)

    save_facets(plots, 2, "/tmp/dv701_f72.png")
    save_facets(plots, 2, "/tmp/dv701_f144.png", dpi=144.0)
    assert_equal(_png_dims("/tmp/dv701_f72.png")[0], 800, "two cells across")
    assert_equal(_png_dims("/tmp/dv701_f144.png")[0], 1600)
    assert_equal(_png_dims("/tmp/dv701_f144.png")[1], 600)

    # A grid's size is given in the call, in points, so dpi scales that.
    save_grid(plots, _two_cells(), 700, 250, "/tmp/dv701_g72.png")
    save_grid(plots, _two_cells(), 700, 250, "/tmp/dv701_g144.png", dpi=144.0)
    assert_equal(_png_dims("/tmp/dv701_g72.png")[0], 700)
    assert_equal(_png_dims("/tmp/dv701_g144.png")[0], 1400)
    assert_equal(_png_dims("/tmp/dv701_g144.png")[1], 500)


def test_dpi_keeps_a_composite_figure_the_same_figure() raises:
    # The same claim `test_dpi_multiplies_the_pixels_and_keeps_the_figure`
    # makes for one plot: more pixels, the same share of them inked --
    # which only holds if the text, strokes and title band scaled too.
    var plots = _roomy_pair()
    var bg = plots[0]._settings.theme.background
    var low = render_facets(plots, 2)
    var high = render_facets(_all_at_dpi(plots, 288.0, "test"), 2)
    assert_equal(high.width, 4 * low.width)
    var a = Float64(_inked(low, bg)) / Float64(low.width * low.height)
    var b = Float64(_inked(high, bg)) / Float64(high.width * high.height)
    assert_true(
        abs(a - b) < 0.02,
        "the inked share moved: " + String(a) + " against " + String(b),
    )


def test_the_vector_formats_ignore_dpi_on_the_composite_savers() raises:
    var plots = _roomy_pair()
    save_layers(plots, "/tmp/dv701_v72.svg")
    save_layers(plots, "/tmp/dv701_v300.svg", dpi=300.0)
    assert_equal(
        _file_text("/tmp/dv701_v72.svg"), _file_text("/tmp/dv701_v300.svg")
    )


def test_a_bad_dpi_names_the_composite_saver() raises:
    var plots = _roomy_pair()
    with assert_raises(contains="save_layers(): dpi must be positive"):
        save_layers(plots, "/tmp/dv701_bad.png", dpi=0.0)
    with assert_raises(contains="save_facets(): dpi must be positive"):
        save_facets(plots, 2, "/tmp/dv701_bad.png", dpi=-1.0)
    with assert_raises(contains="save_grid(): dpi must be positive"):
        save_grid(plots, _two_cells(), 700, 250, "/tmp/dv701_bad.png", dpi=0.0)


def test_tight_shrinks_every_composite_saver_in_every_format() raises:
    var plots = _roomy_pair()
    save_layers(plots, "/tmp/dv701_lt.png", tight=True)
    var l = _png_dims("/tmp/dv701_lt.png")
    assert_true(l[0] < 400 and l[1] < 300, "layers PNG did not crop")
    save_facets(plots, 2, "/tmp/dv701_ft.png", tight=True)
    var f = _png_dims("/tmp/dv701_ft.png")
    assert_true(f[0] < 800 and f[1] < 300, "facets PNG did not crop")
    save_grid(plots, _two_cells(), 900, 400, "/tmp/dv701_gt.png", tight=True)
    var g = _png_dims("/tmp/dv701_gt.png")
    assert_true(g[0] <= 900 and g[1] < 400, "grid PNG did not crop")

    # The vector formats crop too. Read the root element alone: the
    # full-size background rect is still drawn, translated, inside the
    # cropped document, so its width="400" is in both files.
    save_layers(plots, "/tmp/dv701_lt.svg", tight=True)
    var root = _svg_root(_file_text("/tmp/dv701_lt.svg"))
    assert_true('width="400"' not in root, "layers SVG did not crop: " + root)
    assert_true('height="300"' not in root, "layers SVG did not crop: " + root)
    save_layers(plots, "/tmp/dv701_lt.pdf", tight=True)
    assert_true(
        not _bytes_have(
            _file_bytes("/tmp/dv701_lt.pdf"), "/MediaBox [0 0 400 300]"
        ),
        "layers PDF page did not crop",
    )


def test_a_tight_composite_keeps_all_of_its_ink() raises:
    # Cropping must not shave what it cropped to -- the figure title a
    # grid draws above its cells, each cell's title and axis titles.
    var plots = _roomy_pair()
    var bg = plots[0]._settings.theme.background
    var full_l = render_layers(plots)
    var tight_l = _render_layers_tight(plots)
    assert_true(_inked(tight_l, bg) >= _inked(full_l, bg), "layers lost ink")
    var full_f = render_facets(plots, 2)
    var tight_f = _render_facets_tight(plots, 2, False)
    assert_true(_inked(tight_f, bg) >= _inked(full_f, bg), "facets lost ink")
    var cells = _two_cells()
    var no_weights = List[Float64]()
    var full_g = render_grid(plots, cells, 900, 400, title="A figure title")
    var tight_g = _render_grid_tight(
        plots,
        cells,
        900,
        400,
        no_weights,
        no_weights,
        False,
        False,
        "A figure title",
    )
    assert_true(
        tight_g.width < 900 or tight_g.height < 400, "grid did not crop"
    )
    assert_true(
        _inked(tight_g, bg) >= _inked(full_g, bg),
        "grid lost ink, e.g. its figure title",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
