from canvas_mojo.buffer import Canvas

from dataviz_mojo.plot import Plot, _rendered
from dataviz_mojo.scale import _format_fixed, _min_max
from dataviz_mojo.theme import Theme


struct _HistogramBins(Movable):
    """One bin-range label plus count per bin, in bin order -- exactly
    the `(x_categories, y_data)` pair `Plot.encode_histogram()` (plot.
    mojo) assigns onto itself once `_bin_histogram()` returns."""

    var labels: List[String]
    var counts: List[Float64]

    def __init__(out self, var labels: List[String], var counts: List[Float64]):
        self.labels = labels^
        self.counts = counts^


def _bin_histogram(data: List[Float64], bins: Int) raises -> _HistogramBins:
    """Bins `data` into `bins` equal-width intervals -- extracted out
    of `Plot.encode_histogram()`'s body (plot.mojo); see that
    method's docstring for the full contract (raises on empty
    data, zero span, or non-positive `bins`; half-open bins except the
    last, which is closed so `data`'s maximum lands in the last
    bin instead of nowhere; labels formatted to one decimal place via
    `_format_fixed`, the same formatter `LinearScale.ticks()` uses for
    axis labels).
    """
    if len(data) == 0:
        raise Error("Plot.encode_histogram(): data must not be empty")
    if bins <= 0:
        raise Error("Plot.encode_histogram(): bins must be positive (got " + String(bins) + ")")

    var mm = _min_max(data)
    if mm.max == mm.min:
        raise Error(
            "Plot.encode_histogram(): every value in data is identical ("
            + String(mm.min)
            + "), so there's no span to divide into bins"
        )

    var bin_width = (mm.max - mm.min) / Float64(bins)
    var counts = List[Float64]()
    for _ in range(bins):
        counts.append(0.0)
    for v in data:
        var idx = Int((v - mm.min) / bin_width)
        if idx >= bins:
            idx = bins - 1
        counts[idx] += 1.0

    var labels = List[String]()
    for i in range(bins):
        var lo = mm.min + Float64(i) * bin_width
        var hi = mm.min + Float64(i + 1) * bin_width
        labels.append(_format_fixed(lo, 1) + "-" + _format_fixed(hi, 1))

    return _HistogramBins(labels^, counts^)


def histogram(
    data: List[Float64],
    bins: Int = 10,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A histogram -- `Mark.BAR` fed binned counts via `Plot.
    encode_histogram()` (see that method's docstring for the
    binning itself: equal-width intervals, half-open except the last).
    Named after what it plots, not the mark underneath, the same way
    `pie()`/`donut` share `Mark.ARC` -- see this module's `_bin_histogram()` docstring, and plot.mojo's module docstring
    (its "one-call convenience functions" section) for the shared
    `theme`/`width`/`height`/`title`/`x_title`/`y_title` parameters
    every function there takes, this one included."""
    var plot = Plot().mark_bar().encode_histogram(data, bins=bins)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
