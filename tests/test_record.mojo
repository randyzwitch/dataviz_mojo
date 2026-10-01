"""`record()`: a chart drawn once into a `DisplayList` and replayed (#862).

A recording is only useful if replaying it draws what a direct render
draws, so every mark is replayed into a raster canvas and an SVG and
compared with `render()` and `render_svg()` exactly, and a figure with
math labels, annotations and tooltip groups is compared on all three
backends. The rest checks what a retained recording promises beyond
that: it owns its drawing after the chart is gone, an erased chart
records only through its own slot, and a recording is one layout, so a
second size is a second recording rather than a stretched first one.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_not_equal,
    assert_raises,
    assert_true,
)

from canvas.buffer import Canvas
from canvas.display_list import DisplayList
from canvas.text.font_cache import FontCache
from canvas.vector.pdf import PdfCanvas
from canvas.vector.svg import SvgCanvas
from dataviz import (
    OutputFormat,
    Tooltips,
    bar,
    imshow,
    line,
    record,
    render,
    render_pdf,
    render_svg,
    scatter,
)
from dataviz.chart import Chart, ChartLike
from dataviz.marks import Point
from dataviz.rendering import _resolve_supersample
from _mark_registry import _every_mark, _representative_plot
from _test_helpers import _assert_same_canvas, _count_tag


def _replayed_raster[
    C: ChartLike
](plot: C, recording: DisplayList) raises -> Canvas:
    """`recording` replayed the way `render()` draws `plot`: into a
    canvas of the plot's size and background, supersampled at the
    plot's factor."""
    var theme = plot.chart_settings().theme
    var factor = _resolve_supersample(plot.capabilities(), theme, "test")
    var out = Canvas(
        plot.canvas_width(), plot.canvas_height(), theme.background
    )
    var cache = FontCache()
    out.begin_supersampled(factor, theme.background)
    recording.replay(out, cache=cache)
    out.end_supersampled()
    return out^


def _replayed_svg[
    C: ChartLike
](plot: C, recording: DisplayList) raises -> String:
    var svg = SvgCanvas(plot.canvas_width(), plot.canvas_height())
    var cache = FontCache()
    recording.replay(svg, cache=cache)
    return svg.to_string()


def _replayed_pdf[
    C: ChartLike
](plot: C, recording: DisplayList) raises -> List[UInt8]:
    var pdf = PdfCanvas(plot.canvas_width(), plot.canvas_height())
    var cache = FontCache()
    recording.replay(pdf, cache=cache)
    return pdf.to_bytes(compress=False)


def _labeled_scatter() raises -> Chart[Point]:
    """A figure with every kind of drawing that is staged outside the
    mark: math in the title and an axis title (styled runs and a
    fraction rule), reference lines, a band and an arrow with labels,
    and a tooltip group per point."""
    var xs: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var ys: List[Float64] = [2.0, 1.5, 3.5, 2.5, 4.0]
    return (
        scatter(xs, ys, width=480, height=320)
        .labels(
            title="Rate $\\frac{\\Delta y}{\\Delta x}$",
            subtitle="five points",
            x_title="$\\sigma^2$",
            y_title="Count",
        )
        .annotate_line(3.0, "target")
        .annotate_area(1.0, 1.8, "low")
        .annotate_vline(2.5, "cut")
        .annotate_arrow(4.0, 2.5, "peak", 3.2, 3.6)
        .tooltips(Tooltips.ON)
    )


def test_every_mark_replays_to_its_direct_raster() raises:
    for mark in _every_mark():
        var plot = _representative_plot(mark)
        _assert_same_canvas(
            _replayed_raster(plot, record(plot)),
            render(plot),
            mark.name() + " raster replay",
        )


def test_every_mark_replays_to_its_direct_svg() raises:
    for mark in _every_mark():
        var plot = _representative_plot(mark)
        assert_equal(
            _replayed_svg(plot, record(plot, OutputFormat.SVG)),
            render_svg(plot).to_string(),
            mark.name() + " SVG replay",
        )


def test_text_annotations_and_groups_replay_on_every_backend() raises:
    var plot = _labeled_scatter()
    _assert_same_canvas(
        _replayed_raster(plot, record(plot)), render(plot), "raster"
    )
    var svg = _replayed_svg(plot, record(plot, OutputFormat.SVG))
    assert_equal(svg, render_svg(plot).to_string())
    # Equal markup is the order claim; this is the check that the
    # figure has what the claim is about.
    assert_true(_count_tag(svg, "tspan") > 0, "math runs")
    assert_true(_count_tag(svg, "g") > 5, "tooltip groups")
    var direct = render_pdf(plot)
    assert_equal(
        _replayed_pdf(plot, record(plot, OutputFormat.PDF)),
        direct.to_bytes(compress=False),
    )


def test_an_erased_chart_records_through_its_own_slot() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var typed = bar(cats, vals)
    var erased = bar(cats, vals).erased_with[display_list=True]()
    assert_equal(
        _replayed_svg(typed, record(typed, OutputFormat.SVG)),
        _replayed_svg(erased, record(erased, OutputFormat.SVG)),
    )
    # `erased()` binds the four output targets and not this one; the
    # slot refuses instead of drawing through another target's.
    with assert_raises(contains="erased_with[display_list=True]"):
        _ = record(bar(cats, vals).erased())


def _recorded_and_dropped() raises -> DisplayList:
    """A recording whose chart, data and labels are all gone by the
    time the caller replays it."""
    var plot = _labeled_scatter()
    return record(plot)


def _grid() -> List[List[Float64]]:
    """Large enough that a vector recording draws it as one image."""
    var z = List[List[Float64]]()
    for r in range(40):
        var row = List[Float64]()
        for c in range(40):
            row.append(Float64((r * 7 + c * 3) % 23))
        z.append(row^)
    return z^


def _image_recorded_and_dropped() raises -> DisplayList:
    var plot = imshow(_grid(), width=360, height=320)
    return record(plot, OutputFormat.SVG)


def test_a_recording_owns_its_drawing() raises:
    var recording = _recorded_and_dropped()
    var plot = _labeled_scatter()
    _assert_same_canvas(
        _replayed_raster(plot, recording), render(plot), "after drop"
    )
    # Replaying is repeatable: it does not consume the recording.
    _assert_same_canvas(
        _replayed_raster(plot, recording), render(plot), "second replay"
    )

    var image_recording = _image_recorded_and_dropped()
    var image = imshow(_grid(), width=360, height=320)
    var svg = _replayed_svg(image, image_recording)
    assert_equal(_count_tag(svg, "image"), 1)
    assert_equal(svg, render_svg(image).to_string())


def _wide_xs() -> List[Float64]:
    var xs = List[Float64]()
    for i in range(41):
        xs.append(Float64(i) * 2.5)
    return xs^


def _wide_ys() -> List[Float64]:
    var ys = List[Float64]()
    for i in range(41):
        ys.append(Float64((i * 13) % 17))
    return ys^


def test_a_second_size_is_a_second_layout() raises:
    var narrow = line(_wide_xs(), _wide_ys(), width=100, height=200)
    var wide = line(_wide_xs(), _wide_ys(), width=720, height=200)
    var narrow_recording = record(narrow, OutputFormat.SVG)
    var wide_recording = record(wide, OutputFormat.SVG)

    # Each recording is laid out for its own width: the narrow one thins
    # its x ticks until their labels fit, and the wide one keeps them,
    # which no scaling of the narrow recording could do.
    var narrow_svg = _replayed_svg(narrow, narrow_recording)
    var wide_svg = _replayed_svg(wide, wide_recording)
    assert_true(
        _count_tag(wide_svg, "text") > _count_tag(narrow_svg, "text"),
        "a wider layout keeps more ticks",
    )
    assert_equal(wide_svg, render_svg(wide).to_string())

    # And stretching the narrow one to the wide size is not the wide
    # figure.
    var stretched = Canvas(720, 200, wide.chart_settings().theme.background)
    var cache = FontCache()
    stretched.scale(7.2, 1.0)
    record(narrow).replay(stretched, cache=cache)
    var direct = render(wide)
    var differs = False
    for y in range(direct.height):
        for x in range(direct.width):
            if not (stretched.get_pixel(x, y) == direct.get_pixel(x, y)):
                differs = True
                break
        if differs:
            break
    assert_true(differs, "a stretched narrow recording is the wide figure")
    _assert_same_canvas(
        _replayed_raster(wide, record(wide)), direct, "wide raster"
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
