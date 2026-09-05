"""Raster/SVG layout equivalence, one sweep over every mark (#221).

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
"""

from canvas.buffer import Canvas
from canvas.vector.svg import SvgCanvas
from dataviz import (
    arc_diagram,
    bar,
    barbs,
    beeswarm,
    box,
    bullet,
    bump,
    calendar_heatmap,
    candlestick,
    chord,
    contour,
    contourf,
    corrplot,
    effect_scatter,
    funnel,
    gantt,
    gauge,
    graph,
    grouped_bar,
    heatmap,
    lollipop,
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
from dataviz.colors import WHITE
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    area,
    line,
    scatter,
    _LazyFontCache,
    _render_generic,
)
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_true


comptime _W = 420
comptime _H = 300


def _cats() -> List[String]:
    return ["a", "b", "c"]


def _vals() -> List[Float64]:
    return [3.0, 1.0, 2.0]


def _nested() -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var r0: List[Float64] = [1.0, 2.0, 3.0]
    var r1: List[Float64] = [2.0, 3.0, 1.0]
    out.append(r0^)
    out.append(r1^)
    return out^


def _representative_plot(mark: Mark) raises -> Plot:
    """One minimal, valid `Plot` per mark, built through the mark's own
    one-call function so the shape is whatever that function guarantees
    rather than something hand-assembled here.

    Every plot is the same size and uses the default `Theme`, so the two
    backends are compared on identical input in every respect but the
    target.

    Args:
        mark: The mark to build a plot for.

    Returns:
        A renderable `Plot` using `mark`.

    Raises:
        Error: `mark` has no entry here -- see the module docstring.
    """
    var cats = _cats()
    var vals = _vals()
    var xs: List[Float64] = [1.0, 2.0, 3.0]
    var ys: List[Float64] = [2.0, 1.0, 3.0]
    var series: List[String] = ["s1", "s2"]

    if mark == Mark.POINT:
        return scatter(xs, ys, width=_W, height=_H)
    if mark == Mark.LINE:
        return line(xs, ys, width=_W, height=_H)
    if mark == Mark.AREA:
        return area(xs, ys, width=_W, height=_H)
    if mark == Mark.EFFECT_SCATTER:
        return effect_scatter(xs, ys, width=_W, height=_H)
    if mark == Mark.SINGLE_AXIS:
        return single_axis(xs, width=_W, height=_H)
    if mark == Mark.BAR:
        return bar(cats, vals, width=_W, height=_H)
    if mark == Mark.LOLLIPOP:
        return lollipop(cats, vals, width=_W, height=_H)
    if mark == Mark.ARC:
        return pie(cats, vals, width=_W, height=_H)
    if mark == Mark.FUNNEL:
        return funnel(cats, vals, width=_W, height=_H)
    if mark == Mark.NIGHTINGALE:
        return nightingale(cats, vals, width=_W, height=_H)
    if mark == Mark.POLAR_BAR:
        return polarbar(cats, vals, width=_W, height=_H)
    if mark == Mark.RADIALBAR:
        return radialbar(cats, vals, width=_W, height=_H)
    if mark == Mark.WATERFALL:
        return waterfall(cats, vals, width=_W, height=_H)
    if mark == Mark.BOX:
        return box(cats, _box_values(), width=_W, height=_H)
    if mark == Mark.BEESWARM:
        return beeswarm(cats, _box_values(), width=_W, height=_H)
    if mark == Mark.VIOLIN:
        return violin(cats, _box_values(), width=_W, height=_H)
    if mark == Mark.RIDGELINE:
        return ridgeline(cats, _box_values(), width=_W, height=_H)
    if mark == Mark.CANDLESTICK:
        var o: List[Float64] = [1.0, 2.0, 3.0]
        var h: List[Float64] = [4.0, 5.0, 6.0]
        var lo: List[Float64] = [0.5, 1.5, 2.5]
        var cl: List[Float64] = [3.0, 4.0, 5.0]
        return candlestick(cats, o, h, lo, cl, width=_W, height=_H)
    if mark == Mark.BULLET:
        var measures: List[Float64] = [7.0, 5.0, 9.0]
        var targets: List[Float64] = [8.0, 6.0, 8.0]
        var ranges = List[List[Float64]]()
        for _ in range(3):
            var band: List[Float64] = [5.0, 8.0, 10.0]
            ranges.append(band^)
        return bullet(cats, measures, targets, ranges, width=_W, height=_H)
    if mark == Mark.GANTT:
        var start: List[Float64] = [0.0, 2.0, 4.0]
        var end: List[Float64] = [3.0, 5.0, 7.0]
        return gantt(cats, start, end, width=_W, height=_H)
    if mark == Mark.SPAN_CHART:
        var lo2: List[Float64] = [1.0, 2.0, 3.0]
        var hi2: List[Float64] = [4.0, 5.0, 6.0]
        return span_chart(cats, lo2, hi2, width=_W, height=_H)
    if mark == Mark.POPULATION_PYRAMID:
        var left: List[Float64] = [3.0, 2.0, 1.0]
        var right: List[Float64] = [2.0, 3.0, 2.0]
        return population_pyramid(cats, left, right, width=_W, height=_H)
    if mark == Mark.GROUPED_BAR:
        return grouped_bar(cats, series, _nested(), width=_W, height=_H)
    if mark == Mark.STACKED_BAR:
        return stacked_bar(cats, series, _nested(), width=_W, height=_H)
    if mark == Mark.BUMP:
        return bump(cats, series, _nested(), width=_W, height=_H)
    if mark == Mark.STREAMGRAPH:
        return streamgraph(cats, series, _nested(), width=_W, height=_H)
    if mark == Mark.MARIMEKKO:
        return marimekko(cats, series, _nested(), width=_W, height=_H)
    if mark == Mark.HEATMAP:
        var hx: List[String] = ["a", "b", "a", "b"]
        var hy: List[String] = ["x", "x", "y", "y"]
        var hv: List[Float64] = [1.0, 2.0, 3.0, 4.0]
        return heatmap(hx, hy, hv, width=_W, height=_H)
    if mark == Mark.PUNCHCARD:
        var hx2: List[String] = ["a", "b", "a", "b"]
        var hy2: List[String] = ["x", "x", "y", "y"]
        var hs: List[Float64] = [1.0, 2.0, 3.0, 4.0]
        return punchcard(hx2, hy2, hs, width=_W, height=_H)
    if mark == Mark.CALENDAR_HEATMAP:
        var dates: List[String] = ["2024-01-01", "2024-01-02", "2024-01-03"]
        return calendar_heatmap(dates, vals, width=_W, height=_H)
    if mark == Mark.CORRPLOT:
        var matrix = List[List[Float64]]()
        var m0: List[Float64] = [1.0, 0.5]
        var m1: List[Float64] = [0.5, 1.0]
        matrix.append(m0^)
        matrix.append(m1^)
        var vars2: List[String] = ["a", "b"]
        return corrplot(vars2, matrix, width=_W, height=_H)
    if mark == Mark.CHORD:
        return chord(
            _edge_from(), _edge_to(), _edge_vals(), width=_W, height=_H
        )
    if mark == Mark.ARC_DIAGRAM:
        return arc_diagram(
            _edge_from(), _edge_to(), _edge_vals(), width=_W, height=_H
        )
    if mark == Mark.GRAPH:
        return graph(
            _edge_from(), _edge_to(), _edge_vals(), width=_W, height=_H
        )
    if mark == Mark.SANKEY:
        return sankey(
            _edge_from(), _edge_to(), _edge_vals(), width=_W, height=_H
        )
    if mark == Mark.SUNBURST:
        return sunburst(_ids(), _parents(), _hier_vals(), width=_W, height=_H)
    if mark == Mark.TREE:
        return tree(_ids(), _parents(), _hier_vals(), width=_W, height=_H)
    if mark == Mark.TREEMAP:
        return treemap(_ids(), _parents(), _hier_vals(), width=_W, height=_H)
    if mark == Mark.POLAR:
        var angle: List[Float64] = [0.0, 1.0, 2.0]
        var radius: List[Float64] = [1.0, 2.0, 3.0]
        return polar(angle, radius, width=_W, height=_H)
    if mark == Mark.RADAR:
        var indicators: List[String] = ["a", "b", "c"]
        var maxes: List[Float64] = [10.0, 10.0, 10.0]
        var one: List[String] = ["s1"]
        var sv = List[List[Float64]]()
        var svr: List[Float64] = [5.0, 7.0, 3.0]
        sv.append(svr^)
        return radar(indicators, maxes, one, sv, width=_W, height=_H)
    if mark == Mark.GAUGE:
        return gauge(42.0, width=_W, height=_H)
    if mark == Mark.PARALLEL:
        var dims: List[String] = ["d1", "d2", "d3"]
        var rows: List[String] = ["r1", "r2"]
        return parallel(_nested(), dims, rows, width=_W, height=_H)
    if mark == Mark.CONTOUR:
        var z = List[List[Float64]]()
        for r in range(6):
            var row = List[Float64]()
            for c in range(7):
                row.append(Float64((r + 1) * (c + 2) % 11))
            z.append(row^)
        return contour(z, level_count=4, width=_W, height=_H)
    if mark == Mark.CONTOURF:
        var zf = List[List[Float64]]()
        for r in range(6):
            var row = List[Float64]()
            for c in range(7):
                row.append(Float64((r + 1) * (c + 2) % 11))
            zf.append(row^)
        return contourf(zf, level_count=4, width=_W, height=_H)
    if mark == Mark.BARBS:
        var u: List[Float64] = [5.0, 10.0, 15.0]
        var v: List[Float64] = [5.0, -10.0, 0.0]
        return barbs(xs, ys, u, v, width=_W, height=_H)

    raise Error(
        "test_backend_equivalence: no representative plot for mark value "
        + String(mark._value)
        + " -- add one to _representative_plot() (see this module's docstring)"
    )


def _box_values() -> List[List[Float64]]:
    var out = List[List[Float64]]()
    for i in range(3):
        var row: List[Float64] = [
            1.0 + Float64(i),
            2.0 + Float64(i),
            4.0 + Float64(i),
            7.0 + Float64(i),
        ]
        out.append(row^)
    return out^


def _edge_from() -> List[String]:
    return ["a", "b"]


def _edge_to() -> List[String]:
    return ["b", "c"]


def _edge_vals() -> List[Float64]:
    return [2.0, 3.0]


def _ids() -> List[String]:
    return ["root", "a", "b"]


def _parents() -> List[String]:
    return ["", "root", "root"]


def _hier_vals() -> List[Float64]:
    return [0.0, 2.0, 3.0]


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
    var raster_cache = _LazyFontCache()
    var vector_cache = _LazyFontCache()
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
    """`Mark.COUNT` has to name the newest mark's value plus one, or the
    sweep above walks a short range and silently stops covering whatever
    was added last.

    That is not hypothetical: `Mark.CONTOUR` (#259) and `Mark.COUNT`
    (#221) landed in separate PRs that could not see each other, so main
    briefly had `CONTOUR = 43` alongside `COUNT = 43` and the sweep
    skipped contour entirely while still reporting itself green. This
    assertion is what then caught `Mark.CONTOURF` (#260): adding it
    failed here until both the constant and this line moved, which is
    the tripwire doing its job on the very next mark.

    Naming the newest mark explicitly is what makes that loud: adding a
    mark after this one fails here until both this line and `COUNT` are
    updated, which is one edit away from the constant itself.
    """
    assert_true(
        Mark.CONTOURF == Mark(Mark.COUNT - 1),
        (
            "Mark.COUNT must be one past the newest mark -- update both when"
            " adding one"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
