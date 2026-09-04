"""Renders a representative mark per family at increasing data sizes and
prints wall-clock render times, to catch the next accidental quadratic
layout the way #188 (an O(n^2) beeswarm layout) and the line-decimation
fix (`_decimate_to_pixel_columns`, plot.mojo -- a 5,000-point line took
1.7s before it existed) were each found by a user first. Run via
`pixi run bench`.

Not part of CI's pass/fail (`pixi run test` doesn't call this): render
time depends on the machine, and a few percent of noise between runs is
normal. This is a manual "run before a release, or after touching a
mark's layout code" check, plus a coarse `--check` mode for that:
`pixi run bench --check` (or `mojo run -I . -I scripts scripts/bench.mojo
--check`) fails if any mark's 10x-larger size took more than 15x as
long to render as its own smaller size -- true O(n) or O(n log n) work
lands well under that; a real O(n^2) blows well past it. `--check`
skips the 100,000-point POINT/LINE sizes (10s+ each already, not worth
paying twice per run just for the ratio check) and only compares
consecutive sizes within the same backend.

Marks covered are the ones this package's own code shape makes most
likely to hide an accidental O(n^2): the edge family (CHORD/ARC_DIAGRAM/
GRAPH/SANKEY, each with its own node/layout pass over the full edge
list), the hierarchy family (TREE/TREEMAP/SUNBURST, each walking
`_HierarchyIndex` recursively), HEATMAP (an n x n cell grid drawn
directly, not through any of the shared axis-frame machinery), BAR
(categorical tick-label measurement scales with category count, see
`_max_label_width`), and BEESWARM/VIOLIN (the two distribution marks
whose per-category layout wasn't checked for this before -- BEESWARM's
own O(n^2) collision pass is exactly what #188 fixed for the *default*
case; this exists so a regression there is caught on demand rather than
by accident again). Not exhaustive over all 42 marks -- see the
Backlog/issue for the full candidate list.

Every size renders through the same one-file `mojo run`, so the
`_render_generic` dispatch tree's own ~50 CPU-s monomorphization cost
(pixi.toml's own `[tasks]` comment) is paid exactly once for the whole
script, not once per size the way 117 separate one-chart programs used
to before the docs pipeline was batched.
"""

from std.time import perf_counter
from std.math import cos, pi, sin

from dataviz import (
    bar,
    beeswarm,
    chord,
    arc_diagram,
    graph,
    sankey,
    tree,
    treemap,
    sunburst,
    heatmap,
    violin,
    scatter,
    line,
)
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from std.sys import argv


comptime _CHECK_MAX_RATIO = 15.0
"""How many times longer a 10x-larger size may take to render before
`--check` calls it a likely quadratic regression -- true O(n)/O(n log n)
work lands well under this; O(n^2) blows well past it. Not a tight
bound: machine noise, GC-free Mojo aside, still varies run to run."""


struct _Timing(Copyable, Movable):
    var mark: String
    var backend: String
    var n: Int
    var seconds: Float64

    def __init__(
        out self, mark: String, backend: String, n: Int, seconds: Float64
    ):
        self.mark = mark
        self.backend = backend
        self.n = n
        self.seconds = seconds


def _linspace(n: Int, lo: Float64, hi: Float64) -> List[Float64]:
    var out = List[Float64](capacity=n)
    if n == 1:
        out.append(lo)
        return out^
    for i in range(n):
        out.append(lo + (hi - lo) * Float64(i) / Float64(n - 1))
    return out^


def _sine(n: Int) -> List[Float64]:
    var out = List[Float64](capacity=n)
    for i in range(n):
        out.append(sin(Float64(i) * 0.1) * 10.0 + Float64(i) * 0.01)
    return out^


def _numbered_categories(n: Int, prefix: String) -> List[String]:
    var out = List[String](capacity=n)
    for i in range(n):
        out.append(prefix + String(i))
    return out^


def _chain_edges(n: Int) -> Tuple[List[String], List[String], List[Float64]]:
    """A chain edge list -- node i to node i+1, for n edges over n+1
    nodes -- for CHORD/ARC_DIAGRAM/GRAPH/SANKEY. Acyclic, so it's valid
    input for SANKEY's own Kahn's-algorithm column layout too.

    Deliberately not a hub-and-spoke star: first-seen node order then
    places every edge between the *next pair* of nodes, so
    ARC_DIAGRAM's arc radius (half the x-distance between its two
    endpoints) and CHORD/GRAPH's edge length both stay roughly constant
    as n grows, rather than every edge to/from one hub spanning a
    radius up to half the whole plot width. A star was tried first and
    produced arc heights (and therefore rasterization cost) that grew
    with the plot's *pixel* span rather than with n, swamping this
    benchmark's actual target (per-edge/per-node algorithmic cost) with
    geometry the real thing this checks for wouldn't cause.
    """
    var from_cats = List[String](capacity=n)
    var to_cats = List[String](capacity=n)
    var values = List[Float64](capacity=n)
    for i in range(n):
        from_cats.append("n" + String(i))
        to_cats.append("n" + String(i + 1))
        values.append(1.0 + Float64(i % 7))
    return (from_cats^, to_cats^, values^)


def _star_hierarchy(n: Int) -> Tuple[List[String], List[String], List[Float64]]:
    """A flat root-plus-n-leaves hierarchy for TREE/TREEMAP/SUNBURST: depth
    2 regardless of n, so it can't hit a recursion-depth limit the way a
    long chain would at n=10,000 (unlike `_chain_edges`, TREE/TREEMAP/
    SUNBURST's own recursive per-node walk has no reason to prefer a
    chain, so there's no matching geometry concern here to avoid).
    """
    var ids = List[String](capacity=n + 1)
    var parents = List[String](capacity=n + 1)
    var values = List[Float64](capacity=n + 1)
    ids.append("root")
    parents.append("")
    values.append(0.0)
    for i in range(n):
        ids.append("leaf" + String(i))
        parents.append("root")
        values.append(1.0 + Float64(i % 5))
    return (ids^, parents^, values^)


def _grid_heatmap(n: Int) -> Tuple[List[String], List[String], List[Float64]]:
    """An roughly-n-cell square grid (side = ceil(sqrt(n))) for HEATMAP,
    since it takes one x category, one y category, and one value per
    cell rather than a size parameter directly.
    """
    var side = 1
    while side * side < n:
        side += 1
    var xs = List[String](capacity=side * side)
    var ys = List[String](capacity=side * side)
    var values = List[Float64](capacity=side * side)
    for row in range(side):
        for col in range(side):
            xs.append("c" + String(col))
            ys.append("r" + String(row))
            values.append(Float64((row * side + col) % 100))
    return (xs^, ys^, values^)


def _record(
    mut timings: List[_Timing],
    mark: String,
    backend: String,
    n: Int,
    seconds: Float64,
):
    timings.append(_Timing(mark, backend, n, seconds))
    print(
        mark + " " + backend + " n=" + String(n) + ": " + String(seconds) + "s"
    )


def _bench_point_and_line(mut timings: List[_Timing], sizes: List[Int]) raises:
    for n in sizes:
        var x = _linspace(n, 0.0, 100.0)
        var y = _sine(n)
        var scatter_plot = scatter(x, y, width=800, height=600)
        var t0 = perf_counter()
        _ = render(scatter_plot)
        _record(timings, "POINT", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(scatter_plot)
        _record(timings, "POINT", "svg", n, perf_counter() - t0)

        var line_plot = line(x, y, width=800, height=600)
        t0 = perf_counter()
        _ = render(line_plot)
        _record(timings, "LINE", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(line_plot)
        _record(timings, "LINE", "svg", n, perf_counter() - t0)


def _bench_bar(mut timings: List[_Timing], sizes: List[Int]) raises:
    for n in sizes:
        var cats = _numbered_categories(n, "cat")
        var vals = _sine(n)
        var plot = bar(cats, vals, width=800, height=600)
        var t0 = perf_counter()
        _ = render(plot)
        _record(timings, "BAR", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(plot)
        _record(timings, "BAR", "svg", n, perf_counter() - t0)


def _bench_distribution(mut timings: List[_Timing], sizes: List[Int]) raises:
    for n in sizes:
        var cats: List[String] = ["only"]
        var vals: List[List[Float64]] = [_sine(n)]
        var bee = beeswarm(cats, vals, width=800, height=600)
        var t0 = perf_counter()
        _ = render(bee)
        _record(timings, "BEESWARM", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(bee)
        _record(timings, "BEESWARM", "svg", n, perf_counter() - t0)

        var vio = violin(cats, vals, width=800, height=600)
        t0 = perf_counter()
        _ = render(vio)
        _record(timings, "VIOLIN", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(vio)
        _record(timings, "VIOLIN", "svg", n, perf_counter() - t0)


def _bench_edges(mut timings: List[_Timing], sizes: List[Int]) raises:
    for n in sizes:
        var edges = _chain_edges(n)

        var chord_plot = chord(
            edges[0].copy(),
            edges[1].copy(),
            edges[2].copy(),
            width=800,
            height=600,
        )
        var t0 = perf_counter()
        _ = render(chord_plot)
        _record(timings, "CHORD", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(chord_plot)
        _record(timings, "CHORD", "svg", n, perf_counter() - t0)

        var arc_plot = arc_diagram(
            edges[0].copy(),
            edges[1].copy(),
            edges[2].copy(),
            width=800,
            height=600,
        )
        t0 = perf_counter()
        _ = render(arc_plot)
        _record(timings, "ARC_DIAGRAM", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(arc_plot)
        _record(timings, "ARC_DIAGRAM", "svg", n, perf_counter() - t0)

        var graph_plot = graph(
            edges[0].copy(),
            edges[1].copy(),
            edges[2].copy(),
            width=800,
            height=600,
        )
        t0 = perf_counter()
        _ = render(graph_plot)
        _record(timings, "GRAPH", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(graph_plot)
        _record(timings, "GRAPH", "svg", n, perf_counter() - t0)

        var sankey_plot = sankey(
            edges[0].copy(),
            edges[1].copy(),
            edges[2].copy(),
            width=800,
            height=600,
        )
        t0 = perf_counter()
        _ = render(sankey_plot)
        _record(timings, "SANKEY", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(sankey_plot)
        _record(timings, "SANKEY", "svg", n, perf_counter() - t0)


def _bench_hierarchy(mut timings: List[_Timing], sizes: List[Int]) raises:
    for n in sizes:
        var h = _star_hierarchy(n)

        var tree_plot = tree(
            h[0].copy(), h[1].copy(), h[2].copy(), width=800, height=600
        )
        var t0 = perf_counter()
        _ = render(tree_plot)
        _record(timings, "TREE", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(tree_plot)
        _record(timings, "TREE", "svg", n, perf_counter() - t0)

        var treemap_plot = treemap(
            h[0].copy(), h[1].copy(), h[2].copy(), width=800, height=600
        )
        t0 = perf_counter()
        _ = render(treemap_plot)
        _record(timings, "TREEMAP", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(treemap_plot)
        _record(timings, "TREEMAP", "svg", n, perf_counter() - t0)

        var sunburst_plot = sunburst(
            h[0].copy(), h[1].copy(), h[2].copy(), width=800, height=600
        )
        t0 = perf_counter()
        _ = render(sunburst_plot)
        _record(timings, "SUNBURST", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(sunburst_plot)
        _record(timings, "SUNBURST", "svg", n, perf_counter() - t0)


def _bench_heatmap(mut timings: List[_Timing], sizes: List[Int]) raises:
    for n in sizes:
        var grid = _grid_heatmap(n)
        var plot = heatmap(
            grid[0].copy(),
            grid[1].copy(),
            grid[2].copy(),
            width=800,
            height=600,
        )
        var t0 = perf_counter()
        _ = render(plot)
        _record(timings, "HEATMAP", "raster", n, perf_counter() - t0)
        t0 = perf_counter()
        _ = render_svg(plot)
        _record(timings, "HEATMAP", "svg", n, perf_counter() - t0)


def _check_scaling(timings: List[_Timing]) raises -> Bool:
    """A coarse O(n^2) detector: for each (mark, backend), compares every
    pair of consecutive sizes and flags a ~10x size jump that took more
    than `_CHECK_MAX_RATIO` times as long. Prints every comparison it
    makes either way, so a clean run's own output still shows the
    ratios, not just silence.
    """
    var all_ok = True
    for i in range(len(timings)):
        for j in range(i + 1, len(timings)):
            if (
                timings[i].mark != timings[j].mark
                or timings[i].backend != timings[j].backend
            ):
                continue
            if timings[j].n <= timings[i].n:
                continue
            var size_ratio = Float64(timings[j].n) / Float64(timings[i].n)
            if size_ratio < 5.0 or size_ratio > 20.0:
                # Only a genuine ~10x step between two sizes this script
                # actually generated is a meaningful ratio to check.
                continue
            var time_ratio = timings[j].seconds / max(timings[i].seconds, 1e-6)
            var verdict = "OK"
            if time_ratio > _CHECK_MAX_RATIO:
                verdict = "SUSPECT"
                all_ok = False
            print(
                timings[i].mark
                + " "
                + timings[i].backend
                + ": "
                + String(timings[i].n)
                + " -> "
                + String(timings[j].n)
                + " is "
                + String(size_ratio)
                + "x the size, "
                + String(time_ratio)
                + "x the time ["
                + verdict
                + "]"
            )
    return all_ok


def main() raises:
    var check_mode = False
    for a in argv():
        if String(a) == "--check":
            check_mode = True

    # A throwaway render on each backend before any measured size, so a
    # one-time cost unrelated to data size (fontconfig resolving "Sans"
    # to an installed file the first time any label is drawn -- see
    # _max_label_width's own docstring, plot.mojo, for the same warm/cold
    # font-cache gap) doesn't land inside whichever mark happens to run
    # first and make it look artificially slow.
    var warm_x: List[Float64] = [1.0, 2.0]
    var warmup_plot = scatter(warm_x, warm_x, width=100, height=100)
    _ = render(warmup_plot)
    _ = render_svg(warmup_plot)

    var small_sizes: List[Int] = [100, 1000, 10000]
    var point_line_sizes: List[Int] = [100, 1000, 10000] if check_mode else [
        100,
        1000,
        10000,
        100000,
    ]

    var timings = List[_Timing]()
    _bench_point_and_line(timings, point_line_sizes)
    _bench_bar(timings, small_sizes)
    _bench_distribution(timings, small_sizes)
    _bench_edges(timings, small_sizes)
    _bench_hierarchy(timings, small_sizes)
    _bench_heatmap(timings, small_sizes)

    if check_mode:
        print("")
        print("=== --check: consecutive-size scaling ratios ===")
        var ok = _check_scaling(timings)
        if not ok:
            raise Error(
                "bench.mojo --check: at least one mark's render time scaled"
                " worse than "
                + String(_CHECK_MAX_RATIO)
                + "x for a ~10x size increase -- see SUSPECT lines above"
            )
        print("bench.mojo --check: every mark scaled within the expected bound")
