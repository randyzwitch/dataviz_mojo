"""One minimal, valid `Plot` per `Mark`: the registry two sweeps share.

It started inside `test_backend_equivalence.mojo`, which walks every
mark in `_every_mark()` and raises for a mark with no entry, so a mark
added without one fails rather than quietly going untested.
`test_output_digest.mojo` (#570) needs exactly the same coverage for
exactly the same reason, and two copies of a table with one entry per
mark is how one of them ends up missing a mark.

Keep the entries minimal and valid: enough data for the mark to render,
nothing decorative. What either sweep asserts is about the rendering,
not about the data.
"""

from std.math import cos, sin

from canvas.buffer import Canvas
from canvas.text.font_cache import FontCache
from canvas.vector.svg import SvgCanvas
from dataviz.chart import AnyChart, Chart
from dataviz.mark_type import MarkType
from dataviz.core.colors import WHITE
from dataviz.core.cluster import linkage
from dataviz.core.mark import Mark
from dataviz.binned.histogram import bin_edges
from dataviz.plot import Plot
from dataviz import (
    area,
    line,
    scatter,
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
    plot3d,
    rugplot,
    scatter3d,
    bar3d,
    fill_between3d,
    quiver3d,
    stem3d,
    surface3d,
    trisurf3d,
    voxels,
    wire3d,
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
from dataviz.core.theme import Theme
from dataviz.core.validate import _step_setter_name
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


def _every_mark() -> List[Mark]:
    """Every `Mark` constant, in value order: what the sweeps walk.

    The one list of marks the tests keep. It cannot silently fall
    behind `core/mark.mojo`: `test_every_mark_is_listed_once_in_value_order`
    requires exactly `Mark.COUNT` entries valued `0` to `COUNT - 1` in
    order, with distinct names, so a mark added with `COUNT` raised but
    not listed here fails, and so does one listed out of place.
    """
    return [
        Mark.POINT,
        Mark.LINE,
        Mark.BAR,
        Mark.AREA,
        Mark.ARC,
        Mark.LOLLIPOP,
        Mark.WATERFALL,
        Mark.BOX,
        Mark.CANDLESTICK,
        Mark.BULLET,
        Mark.GANTT,
        Mark.GROUPED_BAR,
        Mark.STACKED_BAR,
        Mark.POPULATION_PYRAMID,
        Mark.HEATMAP,
        Mark.CHORD,
        Mark.SINGLE_AXIS,
        Mark.EFFECT_SCATTER,
        Mark.FUNNEL,
        Mark.BUMP,
        Mark.STREAMGRAPH,
        Mark.BEESWARM,
        Mark.VIOLIN,
        Mark.RIDGELINE,
        Mark.NIGHTINGALE,
        Mark.POLAR_BAR,
        Mark.POLAR,
        Mark.RADAR,
        Mark.GAUGE,
        Mark.PARALLEL,
        Mark.SPAN_CHART,
        Mark.CALENDAR_HEATMAP,
        Mark.CORRPLOT,
        Mark.PUNCHCARD,
        Mark.MARIMEKKO,
        Mark.SUNBURST,
        Mark.TREE,
        Mark.TREEMAP,
        Mark.ARC_DIAGRAM,
        Mark.GRAPH,
        Mark.SANKEY,
        Mark.RADIALBAR,
        Mark.BARBS,
        Mark.CONTOUR,
        Mark.CONTOURF,
        Mark.TRICONTOUR,
        Mark.TRICONTOURF,
        Mark.KDE,
        Mark.RUG,
        Mark.TRIPLOT,
        Mark.TRIPCOLOR,
        Mark.ECDF,
        Mark.IMSHOW,
        Mark.PCOLORMESH,
        Mark.EVENTPLOT,
        Mark.POINTPLOT,
        Mark.BOXENPLOT,
        Mark.HIST2D,
        Mark.HEXBIN,
        Mark.QUIVER,
        Mark.HISTOGRAM,
        Mark.STREAMPLOT,
        Mark.DENDROGRAM,
        Mark.SCATTER3D,
        Mark.PLOT3D,
        Mark.SURFACE3D,
        Mark.WIRE3D,
        Mark.TRISURF3D,
        Mark.BAR3D,
        Mark.VOXELS,
        Mark.STEM3D,
        Mark.QUIVER3D,
        Mark.FILL_BETWEEN3D,
    ]


def _erased[M: MarkType](chart: Chart[M]) -> AnyChart:
    """`chart` erased with every render slot bound, the display list's
    included, so a sweep can hand the same entry to `render()`,
    `render_svg()`, `render_pdf()` or `record()` (#862)."""
    return chart.erased_with[
        canvas=True, svg=True, pdf=True, bounds=True, display_list=True
    ]()


def _representative_plot(mark: Mark) raises -> AnyChart:
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
        return _erased(scatter(xs, ys, width=_W, height=_H))
    if mark == Mark.LINE:
        return _erased(line(xs, ys, width=_W, height=_H))
    if mark == Mark.AREA:
        return _erased(area(xs, ys, width=_W, height=_H))
    if mark == Mark.HISTOGRAM:
        return _erased(histogram(ys, bins=4, width=_W, height=_H))
    if mark == Mark.EFFECT_SCATTER:
        return _erased(effect_scatter(xs, ys, width=_W, height=_H))
    if mark == Mark.SINGLE_AXIS:
        return _erased(single_axis(xs, width=_W, height=_H))
    if mark == Mark.BAR:
        return _erased(bar(cats, vals, width=_W, height=_H))
    if mark == Mark.LOLLIPOP:
        return _erased(lollipop(cats, vals, width=_W, height=_H))
    if mark == Mark.POINTPLOT:
        return _erased(pointplot(cats, vals, width=_W, height=_H))
    if mark == Mark.ARC:
        return _erased(pie(cats, vals, width=_W, height=_H))
    if mark == Mark.FUNNEL:
        return _erased(funnel(cats, vals, width=_W, height=_H))
    if mark == Mark.NIGHTINGALE:
        return _erased(nightingale(cats, vals, width=_W, height=_H))
    if mark == Mark.POLAR_BAR:
        return _erased(polarbar(cats, vals, width=_W, height=_H))
    if mark == Mark.RADIALBAR:
        return _erased(radialbar(cats, vals, width=_W, height=_H))
    if mark == Mark.WATERFALL:
        return _erased(waterfall(cats, vals, width=_W, height=_H))
    if mark == Mark.BOX:
        return _erased(box(cats, _box_values(), width=_W, height=_H))
    if mark == Mark.BOXENPLOT:
        return _erased(boxenplot(cats, _box_values(), width=_W, height=_H))
    if mark == Mark.BEESWARM:
        return _erased(beeswarm(cats, _box_values(), width=_W, height=_H))
    if mark == Mark.VIOLIN:
        return _erased(violin(cats, _box_values(), width=_W, height=_H))
    if mark == Mark.RIDGELINE:
        return _erased(ridgeline(cats, _box_values(), width=_W, height=_H))
    if mark == Mark.CANDLESTICK:
        var o: List[Float64] = [1.0, 2.0, 3.0]
        var h: List[Float64] = [4.0, 5.0, 6.0]
        var lo: List[Float64] = [0.5, 1.5, 2.5]
        var cl: List[Float64] = [3.0, 4.0, 5.0]
        return _erased(candlestick(cats, o, h, lo, cl, width=_W, height=_H))
    if mark == Mark.BULLET:
        var measures: List[Float64] = [7.0, 5.0, 9.0]
        var targets: List[Float64] = [8.0, 6.0, 8.0]
        var ranges = List[List[Float64]]()
        for _ in range(3):
            var band: List[Float64] = [5.0, 8.0, 10.0]
            ranges.append(band^)
        return _erased(
            bullet(cats, measures, targets, ranges, width=_W, height=_H)
        )
    if mark == Mark.GANTT:
        var start: List[Float64] = [0.0, 2.0, 4.0]
        var end: List[Float64] = [3.0, 5.0, 7.0]
        return _erased(gantt(cats, start, end, width=_W, height=_H))
    if mark == Mark.SPAN_CHART:
        var lo2: List[Float64] = [1.0, 2.0, 3.0]
        var hi2: List[Float64] = [4.0, 5.0, 6.0]
        return _erased(span_chart(cats, lo2, hi2, width=_W, height=_H))
    if mark == Mark.POPULATION_PYRAMID:
        var left: List[Float64] = [3.0, 2.0, 1.0]
        var right: List[Float64] = [2.0, 3.0, 2.0]
        return _erased(
            population_pyramid(cats, left, right, width=_W, height=_H)
        )
    if mark == Mark.GROUPED_BAR:
        return _erased(
            grouped_bar(cats, series, _nested(), width=_W, height=_H)
        )
    if mark == Mark.STACKED_BAR:
        return _erased(
            stacked_bar(cats, series, _nested(), width=_W, height=_H)
        )
    if mark == Mark.BUMP:
        return _erased(bump(cats, series, _nested(), width=_W, height=_H))
    if mark == Mark.STREAMGRAPH:
        return _erased(
            streamgraph(cats, series, _nested(), width=_W, height=_H)
        )
    if mark == Mark.MARIMEKKO:
        return _erased(marimekko(cats, series, _nested(), width=_W, height=_H))
    if mark == Mark.HEATMAP:
        var hx: List[String] = ["a", "b", "a", "b"]
        var hy: List[String] = ["x", "x", "y", "y"]
        var hv: List[Float64] = [1.0, 2.0, 3.0, 4.0]
        return _erased(heatmap(hx, hy, hv, width=_W, height=_H))
    if mark == Mark.PUNCHCARD:
        var hx2: List[String] = ["a", "b", "a", "b"]
        var hy2: List[String] = ["x", "x", "y", "y"]
        var hs: List[Float64] = [1.0, 2.0, 3.0, 4.0]
        return _erased(punchcard(hx2, hy2, hs, width=_W, height=_H))
    if mark == Mark.CALENDAR_HEATMAP:
        var dates: List[String] = ["2024-01-01", "2024-01-02", "2024-01-03"]
        return _erased(calendar_heatmap(dates, vals, width=_W, height=_H))
    if mark == Mark.CORRPLOT:
        var matrix = List[List[Float64]]()
        var m0: List[Float64] = [1.0, 0.5]
        var m1: List[Float64] = [0.5, 1.0]
        matrix.append(m0^)
        matrix.append(m1^)
        var vars2: List[String] = ["a", "b"]
        return _erased(corrplot(vars2, matrix, width=_W, height=_H))
    if mark == Mark.CHORD:
        return _erased(
            chord(_edge_from(), _edge_to(), _edge_vals(), width=_W, height=_H)
        )
    if mark == Mark.ARC_DIAGRAM:
        return _erased(
            arc_diagram(
                _edge_from(), _edge_to(), _edge_vals(), width=_W, height=_H
            )
        )
    if mark == Mark.GRAPH:
        return _erased(
            graph(_edge_from(), _edge_to(), _edge_vals(), width=_W, height=_H)
        )
    if mark == Mark.SANKEY:
        return _erased(
            sankey(_edge_from(), _edge_to(), _edge_vals(), width=_W, height=_H)
        )
    if mark == Mark.SUNBURST:
        return _erased(
            sunburst(_ids(), _parents(), _hier_vals(), width=_W, height=_H)
        )
    if mark == Mark.TREE:
        return _erased(
            tree(_ids(), _parents(), _hier_vals(), width=_W, height=_H)
        )
    if mark == Mark.TREEMAP:
        return _erased(
            treemap(_ids(), _parents(), _hier_vals(), width=_W, height=_H)
        )
    if mark == Mark.POLAR:
        var angle: List[Float64] = [0.0, 1.0, 2.0]
        var radius: List[Float64] = [1.0, 2.0, 3.0]
        return _erased(polar(angle, radius, width=_W, height=_H))
    if mark == Mark.RADAR:
        var indicators: List[String] = ["a", "b", "c"]
        var maxes: List[Float64] = [10.0, 10.0, 10.0]
        var one: List[String] = ["s1"]
        var sv = List[List[Float64]]()
        var svr: List[Float64] = [5.0, 7.0, 3.0]
        sv.append(svr^)
        return _erased(radar(indicators, maxes, one, sv, width=_W, height=_H))
    if mark == Mark.GAUGE:
        return _erased(gauge(42.0, width=_W, height=_H))
    if mark == Mark.PARALLEL:
        var dims: List[String] = ["d1", "d2", "d3"]
        var rows: List[String] = ["r1", "r2"]
        return _erased(parallel(_nested(), dims, rows, width=_W, height=_H))
    if mark == Mark.CONTOUR:
        var z = List[List[Float64]]()
        for r in range(6):
            var row = List[Float64]()
            for c in range(7):
                row.append(Float64((r + 1) * (c + 2) % 11))
            z.append(row^)
        return _erased(contour(z, level_count=4, width=_W, height=_H))
    if mark == Mark.CONTOURF:
        var zf = List[List[Float64]]()
        for r in range(6):
            var row = List[Float64]()
            for c in range(7):
                row.append(Float64((r + 1) * (c + 2) % 11))
            zf.append(row^)
        return _erased(contourf(zf, level_count=4, width=_W, height=_H))
    if mark == Mark.IMSHOW:
        var zi = List[List[Float64]]()
        for r in range(5):
            var row = List[Float64]()
            for c in range(7):
                row.append(Float64((r + 1) * (c + 2) % 11))
            zi.append(row^)
        return _erased(imshow(zi, width=_W, height=_H))
    if mark == Mark.PCOLORMESH:
        var zm = List[List[Float64]]()
        for r in range(5):
            var row = List[Float64]()
            for c in range(7):
                row.append(Float64((r + 1) * (c + 2) % 11))
            zm.append(row^)
        # Deliberately uneven: a regular mesh would lay out the same as
        # Mark.IMSHOW and prove nothing this sweep does not already
        # cover.
        # Starting at 1 rather than 0 so every edge is positive and the
        # same mesh can be asked for a log axis (#687). The y edges below
        # already start at 1.
        var mesh_x = List[Float64]()
        var mesh_acc = 1.0
        for c in range(8):
            mesh_x.append(mesh_acc)
            mesh_acc += 1.0 + Float64(c) * 0.4
        var mesh_y = List[Float64]()
        for r in range(6):
            mesh_y.append(Float64(r) * Float64(r) + 1.0)
        return _erased(pcolormesh(mesh_x, mesh_y, zm, width=_W, height=_H))
    if mark == Mark.HIST2D:
        var hx = List[Float64]()
        var hy = List[Float64]()
        for i in range(400):
            var t = Float64(i)
            # Plus 1 so every value is positive and the same plot can be
            # asked for a log axis (#718).
            hx.append((t * 7.0) % 23.0 + (t * 3.0) % 5.0 + 1.0)
            hy.append((t * 11.0) % 17.0 + (t * 2.0) % 3.0 + 1.0)
        # Explicit edges rather than hist2d(bins=8): hist2d() refuses a
        # log axis added afterwards over bins it chose in linear units,
        # while edges a caller gives are drawn as given (#718).
        return _erased(
            (
                Plot()
                .mark_hist2d()
                .encode_hist2d(hx, hy, bin_edges(hx, 8), bin_edges(hy, 8))
                .size(_W, _H)
            )
        )
    if mark == Mark.HEXBIN:
        var bx = List[Float64]()
        var by = List[Float64]()
        for i in range(400):
            var t = Float64(i)
            # Plus 1 so every value is positive and the same plot can be
            # asked for a log axis (#718).
            bx.append((t * 7.0) % 23.0 + (t * 3.0) % 5.0 + 1.0)
            by.append((t * 11.0) % 17.0 + (t * 2.0) % 3.0 + 1.0)
        return _erased(hexbin(bx, by, gridsize=8, width=_W, height=_H))
    if mark == Mark.TRICONTOUR:
        var tx = List[Float64]()
        var ty = List[Float64]()
        var tz = List[Float64]()
        for i in range(24):
            var a = Float64(i % 6)
            var b = Float64((i * 5) % 7)
            tx.append(a)
            ty.append(b)
            tz.append(a * b)
        return _erased(
            tricontour(tx, ty, tz, level_count=3, width=_W, height=_H)
        )
    if mark == Mark.TRICONTOURF:
        var fx = List[Float64]()
        var fy = List[Float64]()
        var fz = List[Float64]()
        for i in range(24):
            var a = Float64(i % 6)
            var b = Float64((i * 5) % 7)
            fx.append(a)
            fy.append(b)
            fz.append(a * b)
        return _erased(
            tricontourf(fx, fy, fz, level_count=3, width=_W, height=_H)
        )
    if mark == Mark.TRIPLOT:
        var mx = List[Float64]()
        var my = List[Float64]()
        for i in range(24):
            mx.append(Float64(i % 6))
            my.append(Float64((i * 5) % 7))
        return _erased(triplot(mx, my, width=_W, height=_H))
    if mark == Mark.TRIPCOLOR:
        var px = List[Float64]()
        var py = List[Float64]()
        var pz = List[Float64]()
        for i in range(24):
            var a = Float64(i % 6)
            var b = Float64((i * 5) % 7)
            px.append(a)
            py.append(b)
            pz.append(a * b)
        # Flat shading, which is the default. Do not add gouraud=True
        # here: SVG has no mesh gradient, so canvas draws each face flat
        # at the mean of its corners while raster interpolates, and the
        # two backends diverge on purpose (#398). This sweep exists to
        # catch divergence that is *not* on purpose.
        return _erased(tripcolor(px, py, pz, width=_W, height=_H))
    if mark == Mark.KDE:
        var kv: List[Float64] = [1.0, 2.0, 2.0, 3.0, 5.0, 5.0, 6.0, 8.0]
        return _erased(kdeplot(kv, fill=True, rug=True, width=_W, height=_H))
    if mark == Mark.RUG:
        var rv: List[Float64] = [1.0, 2.0, 2.0, 3.0, 5.0, 5.0, 6.0, 8.0]
        return _erased(rugplot(rv, width=_W, height=_H))
    if mark == Mark.ECDF:
        var ev: List[Float64] = [1.0, 2.0, 2.0, 3.0, 5.0, 5.0, 6.0, 8.0]
        return _erased(ecdf(ev, width=_W, height=_H))
    if mark == Mark.EVENTPLOT:
        var rows = List[List[Float64]]()
        var r0: List[Float64] = [1.0, 2.0, 5.0]
        var r1: List[Float64] = [3.0, 4.0]
        rows.append(r0^)
        rows.append(r1^)
        var row_labels: List[String] = ["a", "b"]
        return _erased(eventplot(row_labels, rows, width=_W, height=_H))
    if mark == Mark.BARBS:
        var u: List[Float64] = [5.0, 10.0, 15.0]
        var v: List[Float64] = [5.0, -10.0, 0.0]
        return _erased(barbs(xs, ys, u, v, width=_W, height=_H))
    if mark == Mark.QUIVER:
        var qu: List[Float64] = [5.0, 10.0, 15.0]
        var qv: List[Float64] = [5.0, -10.0, 0.0]
        return _erased(
            quiver(xs, ys, qu, qv, color_by_magnitude=True, width=_W, height=_H)
        )
    if mark == Mark.STREAMPLOT:
        var sx = List[Float64]()
        for i in range(9):
            sx.append(Float64(i) - 4.0)
        var sy = List[Float64]()
        for j in range(7):
            sy.append(Float64(j) - 3.0)
        var su = List[List[Float64]]()
        var sv = List[List[Float64]]()
        for j in range(len(sy)):
            var urow = List[Float64]()
            var vrow = List[Float64]()
            for i in range(len(sx)):
                urow.append(-sy[j])
                vrow.append(sx[i])
            su.append(urow^)
            sv.append(vrow^)
        return _erased(streamplot(sx, sy, su, sv, width=_W, height=_H))

    if mark == Mark.DENDROGRAM:
        # Four rows that cluster into two obvious pairs, so the merge
        # tree has a shape rather than a chain. `linkage` does the
        # clustering; this mark draws the tree it returns.
        var rows = List[List[Float64]]()
        var seeds: List[Float64] = [0.0, 0.4, 5.0, 5.6]
        for i in range(len(seeds)):
            var row = List[Float64]()
            for k in range(3):
                row.append(seeds[i] + Float64(k) * 0.1)
            rows.append(row^)
        var labels: List[String] = ["a", "b", "c", "d"]
        return _erased(
            (
                Plot()
                .mark_dendrogram()
                .encode_dendrogram(linkage(rows), labels)
                .size(_W, _H)
            )
        )

    if mark == Mark.SCATTER3D or mark == Mark.PLOT3D:
        # A helix: every one of the three columns varies, and the curve
        # passes both in front of and behind itself, so a projection
        # that dropped an axis or sorted depth backwards would show.
        var hx = List[Float64]()
        var hy = List[Float64]()
        var hz = List[Float64]()
        for i in range(40):
            var t = Float64(i) * 0.3
            hx.append(cos(t))
            hy.append(sin(t))
            hz.append(Float64(i) * 0.05)
        if mark == Mark.SCATTER3D:
            return _erased(scatter3d(hx, hy, hz, width=_W, height=_H))
        return _erased(plot3d(hx, hy, hz, width=_W, height=_H))

    if mark == Mark.TRISURF3D:
        # Integer coordinates, like every other triangulated mark here,
        # and deliberately not the helix above. A helix's points are
        # cocircular, which is where the in-circle test sits on its
        # tolerance boundary: a last-ulp difference between two
        # platforms' cos and sin would flip which triangles come out and
        # move this digest on one platform only. These coordinates are
        # bit-identical everywhere.
        var sx = List[Float64]()
        var sy = List[Float64]()
        var sz = List[Float64]()
        for i in range(24):
            var a = Float64(i % 6)
            var b = Float64((i * 5) % 7)
            sx.append(a)
            sy.append(b)
            sz.append(a * b)
        return _erased(trisurf3d(sx, sy, sz, width=_W, height=_H))

    if mark == Mark.SURFACE3D or mark == Mark.WIRE3D:
        # A saddle: it rises along one axis and falls along the other,
        # so a surface drawn with the two lattice axes swapped, or with
        # z read off the wrong index, comes out visibly different.
        var grid = List[List[Float64]]()
        for r in range(6):
            var row = List[Float64]()
            for c in range(6):
                var u = (Float64(c) - 2.5) / 2.5
                var v = (Float64(r) - 2.5) / 2.5
                row.append(u * u - v * v)
            grid.append(row^)
        if mark == Mark.SURFACE3D:
            return _erased(surface3d(grid, width=_W, height=_H))
        return _erased(wire3d(grid, width=_W, height=_H))

    if mark == Mark.BAR3D:
        # Heights that differ across both axes, so a bar drawn at the
        # wrong (x, y) or scaled off the wrong column would show. Two
        # bars are deliberately the tallest and the shortest at
        # opposite corners, which is what a broken depth sort scrambles.
        var bx = List[Float64]()
        var by = List[Float64]()
        var bz = List[Float64]()
        for r in range(3):
            for c in range(4):
                bx.append(Float64(c))
                by.append(Float64(r))
                bz.append(Float64((c * 2 + r * 3) % 5 + 1))
        return _erased(bar3d(bx, by, bz, width=_W, height=_H))

    if mark == Mark.VOXELS:
        # A staircase, so every layer differs from the one below it and
        # the culling has both interior and exterior faces to sort out.
        var grid = List[List[List[Bool]]]()
        for layer in range(4):
            var rows = List[List[Bool]]()
            for row in range(4):
                var cols = List[Bool]()
                for col in range(4):
                    cols.append(col >= layer and row >= layer)
                rows.append(cols^)
            grid.append(rows^)
        return _erased(voxels(grid, width=_W, height=_H))

    if mark == Mark.STEM3D:
        # Heights that rise and fall around the track, so a stem drawn
        # from the wrong foot or to the wrong head would show.
        var sx = List[Float64]()
        var sy = List[Float64]()
        var sz = List[Float64]()
        for i in range(16):
            var a = Float64(i % 4)
            var b = Float64((i * 3) % 5)
            sx.append(a)
            sy.append(b)
            sz.append(Float64((i * 7) % 6) + 1.0)
        return _erased(stem3d(sx, sy, sz, width=_W, height=_H))

    if mark == Mark.QUIVER3D:
        # A field that turns about z: every arrow points somewhere
        # different, so a component dropped or swapped would show.
        var qx = List[Float64]()
        var qy = List[Float64]()
        var qz = List[Float64]()
        var qu = List[Float64]()
        var qv = List[Float64]()
        var qw = List[Float64]()
        for k in range(2):
            for j in range(3):
                for i in range(3):
                    var px = Float64(i) - 1.0
                    var py = Float64(j) - 1.0
                    qx.append(px)
                    qy.append(py)
                    qz.append(Float64(k))
                    qu.append(-py * 0.4)
                    qv.append(px * 0.4)
                    qw.append(0.3)
        return _erased(quiver3d(qx, qy, qz, qu, qv, qw, width=_W, height=_H))

    if mark == Mark.FILL_BETWEEN3D:
        # Two curves that stay apart, so the ribbon has a consistent
        # width and a fold would be visible as a pinch.
        var ax = List[Float64]()
        var ay = List[Float64]()
        var az = List[Float64]()
        var bx = List[Float64]()
        var by = List[Float64]()
        var bz = List[Float64]()
        for i in range(12):
            var t = Float64(i)
            ax.append(t)
            ay.append(Float64(i % 3))
            az.append(Float64((i * 5) % 7))
            bx.append(t)
            by.append(Float64(i % 3) + 2.0)
            bz.append(Float64((i * 5) % 7) + 1.0)
        return _erased(
            fill_between3d(ax, ay, az, bx, by, bz, width=_W, height=_H)
        )

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
