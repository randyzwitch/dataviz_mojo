"""Price `record()` beside direct rendering, for a small and a dense chart
(#862).

Run with `pixi run bench-record`. For each chart it reports what the
recording retains (commands, shared resources, estimated bytes), then
the median time of: a direct `render()`, one `record()`, a replay of
that recording into a fresh supersampled canvas the way `render()`
draws, and the same pair for SVG. A retained widget pays `record()`
once per content change and a replay per repaint, so the replay rows
beside the direct ones are the comparison that matters.

Passes interleave the arms, so drift on a busy machine lands on all of
them; run it on an idle one (benchmarks/METHODOLOGY.md).

This is a manual benchmark and is not part of `pixi run test`.
"""

from std.math import sin
from std.time import perf_counter

from canvas.buffer import Canvas
from canvas.display_list import DisplayList
from canvas.text.font_cache import FontCache
from canvas.vector.svg import SvgCanvas
from dataviz import OutputFormat, bar, record, render, render_svg, scatter
from dataviz.chart import ChartLike
from dataviz.rendering import _resolve_supersample


comptime _PASSES = 25


def _median(var values: List[Float64]) -> Float64:
    sort(values)
    return values[len(values) // 2]


def _ms(seconds: Float64) -> String:
    return String(Float64(Int(seconds * 1.0e5 + 0.5)) / 100.0) + " ms"


def _replay_raster[C: ChartLike](plot: C, recording: DisplayList) raises:
    var theme = plot.chart_settings().theme
    var factor = _resolve_supersample(plot.capabilities(), theme, "bench")
    var out = Canvas(
        plot.canvas_width(), plot.canvas_height(), theme.background
    )
    var cache = FontCache()
    out.begin_supersampled(factor, theme.background)
    recording.replay(out, cache=cache)
    out.end_supersampled()
    _ = out.get_pixel(0, 0)


def _replay_svg[C: ChartLike](plot: C, recording: DisplayList) raises:
    var svg = SvgCanvas(plot.canvas_width(), plot.canvas_height())
    var cache = FontCache()
    recording.replay(svg, cache=cache)
    _ = svg.to_string()


def _bench[C: ChartLike](name: String, plot: C) raises:
    var raster_recording = record(plot)
    var svg_recording = record(plot, OutputFormat.SVG)
    print(
        name,
        "|",
        raster_recording.command_count(),
        "commands,",
        raster_recording.resource_count(),
        "resources,",
        raster_recording.storage_bytes(),
        "bytes retained",
    )
    var direct = List[Float64]()
    var recording = List[Float64]()
    var replay = List[Float64]()
    var direct_svg = List[Float64]()
    var replay_svg = List[Float64]()
    for _ in range(_PASSES):
        var t0 = perf_counter()
        _ = render(plot).get_pixel(0, 0)
        var t1 = perf_counter()
        _ = record(plot).command_count()
        var t2 = perf_counter()
        _replay_raster(plot, raster_recording)
        var t3 = perf_counter()
        _ = render_svg(plot).to_string()
        var t4 = perf_counter()
        _replay_svg(plot, svg_recording)
        var t5 = perf_counter()
        direct.append(t1 - t0)
        recording.append(t2 - t1)
        replay.append(t3 - t2)
        direct_svg.append(t4 - t3)
        replay_svg.append(t5 - t4)
    print("  direct render()    ", _ms(_median(direct^)))
    print("  record()           ", _ms(_median(recording^)))
    print("  replay to Canvas   ", _ms(_median(replay^)))
    print("  direct render_svg()", _ms(_median(direct_svg^)))
    print("  replay to SvgCanvas", _ms(_median(replay_svg^)))


def main() raises:
    var cats: List[String] = ["north", "south", "east", "west", "central"]
    var vals: List[Float64] = [12.0, 7.0, 15.0, 9.0, 11.0]
    _bench(
        "small: 5-bar chart",
        bar(cats, vals, width=640, height=420).labels(
            title="Sales by region", y_title="Units"
        ),
    )

    var xs = List[Float64](capacity=10000)
    var ys = List[Float64](capacity=10000)
    for i in range(10000):
        xs.append(Float64(i) * 0.01)
        ys.append(sin(Float64(i) * 0.013) * 10.0 + Float64(i % 97) * 0.05)
    _bench(
        "dense: 10,000-point scatter",
        scatter(xs, ys, width=640, height=420)
        .labels(title="Signal", x_title="$t$ (s)", y_title="Amplitude")
        .annotate_line(5.0, "threshold"),
    )
