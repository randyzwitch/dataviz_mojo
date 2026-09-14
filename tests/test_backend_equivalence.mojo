"""Raster/SVG layout equivalence, one sweep over every mark.

Both backends go through the same `_render_generic[T: DrawTarget]`, but
each mark's own tests exercise the two independently, so a divergence
between them is caught only where a mark happens to have a test on the
affected side. This module asserts the thing that must hold for every
mark: laying the same `Plot` out on a `Canvas` and on an `SvgCanvas`
produces the same plot rect and the same text requests.

It compares *layout*, not pixels -- the two backends draw differently by
design, and a bitmap has no `<text>` element to compare against. What
they must agree on is where the mark decided things go, which is exactly
what `_RenderResult` carries.

`_representative_plot` is a registry: one minimal, valid `Plot` per
`Mark`. The sweep walks `Mark(0)` through `Mark(Mark.COUNT - 1)`, so a
mark added without an entry here raises rather than quietly going
untested.

`Mark.name()` is tested here for the same reason and off the
same range: it is the other per-mark table that a new mark has to be
added to, and the failure mode is identical -- a missing entry is
invisible until an error message names the wrong mark. Neither needs a
render, so they cost nothing in this SVG-only module.
"""

from canvas.buffer import Canvas
from canvas.text.font_cache import FontCache
from canvas.vector.svg import SvgCanvas
from dataviz import (
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
    imshow,
    pcolormesh,
    hist2d,
    hexbin,
    histogram,
    quiver,
    streamplot,
    tricontour,
    tricontourf,
    tripcolor,
    triplot,
    kdeplot,
    rugplot,
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
    lollipop,
    pointplot,
    marimekko,
    nightingale,
    parallel,
    pie,
    polar,
    polarbar,
    population_pyramid,
    punchcard,
    radar,
    radialbar,
    ridgeline,
    sankey,
    single_axis,
    span_chart,
    stacked_bar,
    streamgraph,
    sunburst,
    tree,
    treemap,
    violin,
    waterfall,
)
from dataviz.core.colors import WHITE
from dataviz.core.mark import Mark
from dataviz.plot import (
    Plot,
    area,
    line,
    scatter,
    _render_generic,
)
from dataviz.core.theme import Theme
from dataviz.core.validate import _step_setter_name
from std.testing import TestSuite, assert_equal, assert_true


# The per-mark registry lives in _mark_registry.mojo, shared with the
# output-digest sweep (#570): two copies of a table with one entry per
# mark is how one of them ends up missing a mark.
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
