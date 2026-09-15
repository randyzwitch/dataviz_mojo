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
from dataviz import (
    Theme,
    arc_diagram,
    area,
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
    line,
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
    scatter,
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
from dataviz.core.colors import CRIMSON, WHITE
from dataviz.core.mark import Mark
from dataviz.core.theme import Theme
from dataviz.core.validate import _step_setter_name
from dataviz.layout import GridCell, save_grid
from dataviz.facets import save_facets
from dataviz.layers import save_layers
from dataviz.plot import (
    Plot,
    _at_dpi,
    _render_generic,
    _render_into,
    _resolve_supersample,
    area,
    line,
    render,
    render_layers,
    render_pdf,
    save,
    scatter,
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


def test_mark_count_is_one_past_the_newest_mark() raises:
    """Require `Mark.COUNT` to be one greater than the newest mark value."""
    assert_true(
        Mark.STREAMPLOT == Mark(Mark.COUNT - 1),
        (
            "Mark.COUNT must be one past the newest mark -- update both when"
            " adding one"
        ),
    )


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
    var factor = _resolve_supersample(plot, "render")
    var scratch = Canvas(
        plot.width * factor, plot.height * factor, plot._theme.background
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
