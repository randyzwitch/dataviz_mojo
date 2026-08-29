from canvas_mojo.buffer import Canvas

from dataviz_mojo.plot import Plot, _finished
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
    of `Plot.encode_histogram()`'s body (plot.mojo). Raises on empty
    data, zero span, or non-positive `bins`; half-open bins except the
    last, which is closed so `data`'s maximum lands in the last
    bin instead of nowhere; labels formatted to one decimal place via
    `_format_fixed`, the same formatter `LinearScale.ticks()` uses for
    axis labels.
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
) raises -> Plot:
    """A histogram -- `Mark.BAR` fed binned counts via `Plot.
    encode_histogram()` (see that method's docstring for the
    binning itself: equal-width intervals, half-open except the last).
    Named after what it plots, not the mark underneath, the same way
    `pie()`/`donut` share `Mark.ARC`. Takes the same `theme`/`width`/
    `height`/`title`/`x_title`/`y_title` parameters every one-call
    convenience function does (see plot.mojo's module docstring).

    Args:
        data: The raw values to bin -- not pre-counted; binning
            happens internally.
        bins: How many equal-width intervals to divide `data`'s range
            into (half-open except the last, which includes its
            upper edge).
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz_mojo import histogram
        from dataviz_mojo.plot import save
        from dataviz_mojo.colors import REBECCAPURPLE
        from dataviz_mojo.theme import Theme

        def main() raises:
            # Exam scores out of 100 -- a real bell-ish spread, not a uniform
            # or already-sorted list, so the binning has genuine work to do.
            var scores: List[Float64] = [
                52.0, 61.0, 65.0, 68.0, 70.0, 71.0, 72.0, 74.0, 75.0, 76.0,
                77.0, 78.0, 78.0, 79.0, 80.0, 81.0, 81.0, 82.0, 83.0, 84.0,
                85.0, 86.0, 87.0, 88.0, 89.0, 90.0, 91.0, 93.0, 95.0, 98.0,
            ]

            var c = histogram(scores, bins=8, theme=Theme(mark_color=REBECCAPURPLE))
            save(c, "docs/src/examples/out_histogram.svg")
        ```
    """
    var plot = Plot().mark_bar().encode_histogram(data, bins=bins)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
