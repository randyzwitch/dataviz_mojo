"""Histogram binning and one-call chart helpers.

The binning behavior matches `numpy.histogram`:

- Every bin is half-open, `[edges[i], edges[i + 1])`, **except the last**,
  which is closed on the right so the sample maximum lands inside the
  histogram instead of falling off it.
- Observations outside `[edges[0], edges[-1]]` are dropped, not clamped
  into the end bins.
- A constant sample gets the range `[v - 0.5, v + 0.5]`.
- `density` normalizes by the total weight of the observations that
  actually landed in a bin, so `sum(value[i] * width[i]) == 1` even when
  some observations fell outside the edges.

"""

from dataviz.array_like import _materialize_scalar_list
from dataviz.plot import Plot, _finished
from dataviz.scale import _format_fixed, _min_max
from dataviz.step_style import StepStyle
from dataviz.theme import Theme


struct HistStat(Copyable, ImplicitlyCopyable, Movable):
    """Select how `histogram_bins()` and `histogram()` normalize bins.

    Here `w[i]` is bin `i`'s weight, `W` is the total included weight,
    and `width[i]` is `edges[i + 1] - edges[i]`:

    | Stat | Bin value | Totals to |
    |---|---|---|
    | `COUNT` | `w[i]` | `W` |
    | `FREQUENCY` | `w[i] / width[i]` | `W` after multiplying by width |
    | `PROBABILITY` | `w[i] / W` | `1` |
    | `PERCENT` | `100 * w[i] / W` | `100` |
    | `DENSITY` | `w[i] / (W * width[i])` | `1` after multiplying by width |

    Use `FREQUENCY` or `DENSITY` to account for unequal bin widths.
    """

    var _value: Int

    comptime COUNT = Self(0)
    """Observation count, or total weight, in each bin."""
    comptime FREQUENCY = Self(1)
    """Observation count or weight per unit of x."""
    comptime PROBABILITY = Self(2)
    """Fraction of included weight in each bin; heights sum to 1."""
    comptime PERCENT = Self(3)
    """Percentage of included weight in each bin; heights sum to 100."""
    comptime DENSITY = Self(4)
    """Probability density; bar areas sum to 1."""

    def __init__(out self, value: Int):
        """Prefer the `COUNT`/`FREQUENCY`/`PROBABILITY`/`PERCENT`/
        `DENSITY` comptime constants over constructing one directly.

        Args:
            value: 0 for COUNT, 1 for FREQUENCY, 2 for PROBABILITY, 3
                for PERCENT, 4 for DENSITY.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        """Whether both name the same stat.

        Args:
            other: The stat to compare against.

        Returns:
            True when they match.
        """
        return self._value == other._value

    def __ne__(self, other: Self) -> Bool:
        """Whether the two name different stats.

        Args:
            other: The stat to compare against.

        Returns:
            True when they differ.
        """
        return self._value != other._value

    def name(self) -> String:
        """This stat's constant name, for error messages and axis
        captions that have to say which one was asked for.

        Returns:
            "COUNT", "FREQUENCY", "PROBABILITY", "PERCENT", "DENSITY",
            or "HistStat(<n>)" for a value outside the five constants.
        """
        if self._value == 0:
            return "COUNT"
        if self._value == 1:
            return "FREQUENCY"
        if self._value == 2:
            return "PROBABILITY"
        if self._value == 3:
            return "PERCENT"
        if self._value == 4:
            return "DENSITY"
        return "HistStat(" + String(self._value) + ")"

    def _normalizes_by_width(self) -> Bool:
        """Whether this stat divides by the bin width (`FREQUENCY`,
        `DENSITY`).

        Returns:
            True for the two per-unit-of-x stats.
        """
        return self._value == 1 or self._value == 4

    def _normalizes_by_total(self) -> Bool:
        """Whether this stat divides by the total binned weight
        (`PROBABILITY`, `PERCENT`, `DENSITY`).

        Returns:
            True for the three stats that need a nonzero total.
        """
        return self._value == 2 or self._value == 3 or self._value == 4


struct HistogramBins(Copyable, Movable, Sized):
    """A binned sample: `len(edges) - 1` bins, `edges` ascending, one
    entry in `values` per bin. What `histogram_bins()` returns and what
    `histogram()` draws.

    Numeric edges rather than the `List[String]` range labels this
    module stored before. A label like `"52.0-57.8"` is a
    formatted view of a number, and every downstream use -- placing a
    bar over the interval it actually covers, sharing an x-domain with a
    density curve, aligning a marginal histogram with the joint plot it
    sits beside -- needs the number back. Rounding it to one decimal
    place for display and then parsing it again would be a lossy round
    trip through a string for no reason.

    `edges` is `bins + 1` long, not one `(lo, hi)` pair per bin, because
    a histogram's bins tile an interval with no gaps and no overlaps:
    the pair form can express a gap or an overlap, which is a state
    nothing here can draw and every consumer would have to check for.
    Unequal widths are fine -- the shared edge is exactly what makes
    them still a tiling.
    """

    var edges: List[Float64]
    """The `bins + 1` bin boundaries, strictly ascending. Bin `i` covers
    `[edges[i], edges[i + 1])`, except the last, which includes
    `edges[-1]`."""
    var values: List[Float64]
    """One value per bin, in `HistStat`'s units."""

    def __init__(out self, var edges: List[Float64], var values: List[Float64]):
        """Construct directly from already-computed columns.

        Args:
            edges: The `bins + 1` boundaries, strictly ascending.
            values: One value per bin.
        """
        self.edges = edges^
        self.values = values^

    def __len__(self) -> Int:
        """How many bins there are.

        Returns:
            `len(edges) - 1`.
        """
        return len(self.edges) - 1

    def width(self, i: Int) -> Float64:
        """Bin `i`'s width.

        Args:
            i: Bin index, `0` through `len(self) - 1`.

        Returns:
            `edges[i + 1] - edges[i]`.
        """
        return self.edges[i + 1] - self.edges[i]

    def center(self, i: Int) -> Float64:
        """Bin `i`'s midpoint -- where a marker or a label for the bin
        goes.

        Computed as `lo + (hi - lo) / 2` rather than `(lo + hi) / 2`:
        the two agree to a rounding step for ordinary data, but the sum
        form overflows to infinity for edges near `Float64`'s maximum
        and the difference form does not.

        Args:
            i: Bin index, `0` through `len(self) - 1`.

        Returns:
            The midpoint of `[edges[i], edges[i + 1]]`.
        """
        return self.edges[i] + (self.edges[i + 1] - self.edges[i]) / 2.0

    def total(self) -> Float64:
        """The sum of every bin's value -- `W` for `COUNT`, `1.0` for
        `PROBABILITY`, `100.0` for `PERCENT`, and a number with no
        meaning of its own for the two width-normalized stats (sum
        `value[i] * width[i]` for those instead).

        Returns:
            `sum(values)`.
        """
        var t = 0.0
        for v in self.values:
            t += v
        return t

    def step_x(self) -> List[Float64]:
        """The x column for drawing this as a staircase: every edge, in
        order, `bins + 1` long. Pair with `step_y()` and
        `mark_area(step=StepStyle.POST)` (or `mark_line`), which is
        exactly what `histogram()` does.

        `POST` is the style that matches: it holds `y[i]` across
        `[x[i], x[i + 1])`, which is the half-open bin `[edges[i],
        edges[i + 1])`. `PRE` would draw every bar shifted one bin left
        and `MID` half a bin left.

        Returns:
            A copy of `edges`.
        """
        return self.edges.copy()

    def step_y(self) -> List[Float64]:
        """The y column for `step_x()`: every bin's value, plus the last
        value repeated so the final plateau has a point to run out to at
        `edges[-1]`.

        `StepStyle.POST` draws `[x[i], x[i + 1])` at `y[i]` and stops at
        the last sample, so without the repeat the rightmost bin would
        be a bar with no top.

        Returns:
            `values` with `values[-1]` appended, `bins + 1` long.
        """
        var ys = self.values.copy()
        ys.append(self.values[len(self.values) - 1])
        return ys^


def _bin_index(value: Float64, edges: List[Float64]) -> Int:
    """Which bin `value` falls in, under the half-open-except-the-last
    rule, or `-1` when it falls outside `[edges[0], edges[-1]]`.

    A binary search over `edges` rather than the `Int((v - lo) /
    bin_width)` arithmetic this module used before. The arithmetic form
    is only defined for equal-width bins, so it could not support
    explicit edges at all; and even for equal widths it answers a
    *different* question than the drawing does, because it reconstructs
    the boundary from `lo` and a width while the chart draws the
    `edges` list. Those two disagree in the last bit often enough to
    matter: `lo=0, hi=1, bins=10` puts `edges[3]` at
    `0.30000000000000004` by repeated stepping and at `0.3` by the
    ratio form, and a sample sitting exactly on the drawn edge then
    lands in a bin on one side of a line it is drawn on the other side
    of. Searching the same `edges` the renderer receives makes that
    disagreement impossible to have.

    Args:
        value: The observation.
        edges: The bin boundaries, strictly ascending, at least 2 long.

    Returns:
        A bin index in `[0, len(edges) - 2]`, or `-1` for an
        out-of-range (or `NaN`) value.
    """
    var last = len(edges) - 1
    # NaN fails both comparisons, so it takes the out-of-range exit --
    # the same "not in any bin" answer numpy's own histogram gives it.
    if not (value >= edges[0] and value <= edges[last]):
        return -1
    if value == edges[last]:
        # The one closed right edge: the sample maximum belongs to the
        # histogram, not past its end.
        return last - 1
    # The largest i with edges[i] <= value, over i in [0, last - 1].
    var lo = 0
    var hi = last - 1
    while lo < hi:
        var mid = (lo + hi + 1) // 2
        if edges[mid] <= value:
            lo = mid
        else:
            hi = mid - 1
    return lo


def uniform_bin_edges(
    min: Float64, max: Float64, bins: Int
) raises -> List[Float64]:
    """`bins + 1` equally spaced boundaries covering `[min, max]` -- the
    explicit-range form of `bin_edges()`, and the way to pin two
    histograms of different samples to the same intervals by hand.

    Boundary `i` is `min + (max - min) * i / bins`. Both endpoints are
    assigned exactly so `edges[0] == min` and `edges[bins] == max`.

    Args:
        min: The left edge of the first bin.
        max: The right edge of the last bin; must be greater than `min`.
        bins: How many intervals to divide `[min, max]` into; must be
            positive.

    Returns:
        `bins + 1` strictly ascending boundaries.

    Raises:
        Error: `bins` is not positive, `max` is not greater than `min`,
            either bound is not finite, or the span is so small relative
            to the bounds that two boundaries round to the same
            `Float64`.
    """
    if bins <= 0:
        raise Error(
            "uniform_bin_edges(): bins must be positive (got "
            + String(bins)
            + ")"
        )
    # _min_max is the package's one chokepoint for NaN/inf; reusing it
    # here keeps the message and the rule identical to every other
    # domain in the library.
    var pair: List[Float64] = [min, max]
    _ = _min_max(pair)
    if not (max > min):
        raise Error(
            "uniform_bin_edges(): max must be greater than min (got min="
            + String(min)
            + ", max="
            + String(max)
            + ")"
        )
    var edges = List[Float64](capacity=bins + 1)
    edges.append(min)
    for i in range(1, bins):
        edges.append(min + (max - min) * Float64(i) / Float64(bins))
    edges.append(max)
    for i in range(bins):
        if not (edges[i + 1] > edges[i]):
            raise Error(
                "uniform_bin_edges(): "
                + String(bins)
                + " bins over ["
                + String(min)
                + ", "
                + String(max)
                + "] collapse -- the span is too small for that many"
                " distinct Float64 boundaries"
            )
    return edges^


def bin_edges(data: List[Float64], bins: Int = 10) raises -> List[Float64]:
    """`bins + 1` equally spaced boundaries covering `data`'s own range.

    A **constant sample** -- every value identical, which includes a
    one-element sample -- gets the range `[v - 0.5, v + 0.5]` rather
    than raising, which is what this module did before. numpy's
    rule, and the right one: a spike at a single value is a real
    distribution with a real answer, and "no span to divide into bins"
    told a caller their data was unplottable when what they wanted to
    see was that it was constant. The half-unit is arbitrary in
    magnitude but not in kind -- it is the only choice that does not
    depend on data the sample does not have.

    Args:
        data: The observations. Only their min and max are read.
        bins: How many intervals to divide the range into; must be
            positive.

    Returns:
        `bins + 1` strictly ascending boundaries.

    Raises:
        Error: `data` is empty, `bins` is not positive, or any value is
            `NaN`/infinite.
    """
    if len(data) == 0:
        raise Error("bin_edges(): data must not be empty")
    var mm = _min_max(data)
    if mm.max == mm.min:
        return uniform_bin_edges(mm.min - 0.5, mm.min + 0.5, bins)
    return uniform_bin_edges(mm.min, mm.max, bins)


def shared_bin_edges(
    samples: List[List[Float64]], bins: Int = 10
) raises -> List[Float64]:
    """One set of boundaries covering every sample in `samples`: the
    smallest value anywhere to the largest value anywhere, in `bins`
    equal intervals.

    Two histograms only compare if their bars line up. Binning each
    sample against its own range gives each one different edges, so a
    bar in one chart covers a different interval than the bar drawn
    beside it -- the comparison the reader makes is then between two
    quantities that were never measured the same way. Feeding these
    edges to `histogram_bins()` for each sample makes the bins
    identical by construction.

    Args:
        samples: One list of observations per group. Empty groups are
            allowed and contribute nothing to the range, as long as at
            least one group has a value.
        bins: How many intervals to divide the combined range into;
            must be positive.

    Returns:
        `bins + 1` strictly ascending boundaries, the same for every
        group.

    Raises:
        Error: `samples` is empty or every group is, `bins` is not
            positive, or any value is `NaN`/infinite.
    """
    var pooled = List[Float64]()
    for s in samples:
        for v in s:
            pooled.append(v)
    if len(pooled) == 0:
        raise Error(
            "shared_bin_edges(): samples must contain at least one"
            " observation across all groups"
        )
    return bin_edges(pooled, bins)


def histogram_bins(
    data: List[Float64],
    edges: List[Float64],
    weights: List[Float64] = List[Float64](),
    stat: HistStat = HistStat.COUNT,
    cumulative: Bool = False,
) raises -> HistogramBins:
    """Bin `data` into the intervals `edges` names, and return the
    numeric edges alongside one value per bin.

    Bin `i` collects every observation in `[edges[i], edges[i + 1])`,
    except the last bin, which is closed on the right so the sample
    maximum lands inside it. Observations outside `[edges[0],
    edges[-1]]` are dropped -- an explicit range is a statement about
    what to show, and folding an outlier into an end bin would draw a
    bar taller than the interval under it justifies.

    `cumulative` accumulates **mass**, never the drawn value: bin `i`
    becomes the running total of the observation weight at or below
    `edges[i + 1]`, re-expressed in `stat`'s units. That distinction
    only shows up for the two width-normalized stats, where the naive
    running sum of the bin values would have units of density times
    bins and would depend on how many bins the caller asked for.
    Accumulating mass instead makes `DENSITY` cumulative the empirical
    CDF (last bin exactly `1.0`) and `FREQUENCY` cumulative the running
    count, matching matplotlib's `hist(cumulative=True, density=...)`
    on both equal- and unequal-width edges.

    Args:
        data: The observations to bin.
        edges: The bin boundaries, strictly ascending, at least 2 long
            -- from `bin_edges()`, `uniform_bin_edges()`,
            `shared_bin_edges()`, or written out by hand for unequal
            widths.
        weights: One nonnegative weight per observation, or empty (the
            default) for one apiece. A weighted bin holds the total
            weight that landed in it, so every stat generalizes without
            a second definition.
        stat: What a bin's value is -- a count, or one of four
            normalizations. See `HistStat`.
        cumulative: Accumulate each bin into the ones before it.

    Returns:
        The bins: a copy of `edges`, and one value per bin.

    Raises:
        Error: `data` is empty; `edges` is shorter than 2 or not
            strictly ascending; `weights` is neither empty nor the same
            length as `data`; any weight is negative or non-finite; any
            value is `NaN`/infinite; or a normalized `stat` was asked
            for and no observation landed in any bin.
    """
    if len(data) == 0:
        raise Error("histogram_bins(): data must not be empty")
    if len(edges) < 2:
        raise Error(
            "histogram_bins(): edges needs at least 2 boundaries to name one"
            " bin (got "
            + String(len(edges))
            + ")"
        )
    _ = _min_max(edges)
    for i in range(len(edges) - 1):
        if not (edges[i + 1] > edges[i]):
            raise Error(
                "histogram_bins(): edges must be strictly ascending -- edges["
                + String(i)
                + "]="
                + String(edges[i])
                + " is not below edges["
                + String(i + 1)
                + "]="
                + String(edges[i + 1])
            )
    var weighted = len(weights) > 0
    if weighted and len(weights) != len(data):
        raise Error(
            "histogram_bins(): weights must be empty or one per observation"
            " (got "
            + String(len(weights))
            + " weights for "
            + String(len(data))
            + " values)"
        )
    if weighted:
        _ = _min_max(weights)
        for w in weights:
            if w < 0.0:
                raise Error(
                    "histogram_bins(): weights must be nonnegative (got "
                    + String(w)
                    + ") -- a negative weight makes a bar that points the"
                    " wrong way and a total that no longer normalizes"
                )
    _ = _min_max(data)

    var nbins = len(edges) - 1
    var mass = List[Float64](capacity=nbins)
    for _ in range(nbins):
        mass.append(0.0)
    var total = 0.0
    for i in range(len(data)):
        var b = _bin_index(data[i], edges)
        if b < 0:
            continue
        var w = weights[i] if weighted else 1.0
        mass[b] += w
        total += w

    if stat._normalizes_by_total() and total <= 0.0:
        raise Error(
            "histogram_bins(): stat="
            + stat.name()
            + " divides by the total binned weight, which is 0 -- no"
            " observation fell inside ["
            + String(edges[0])
            + ", "
            + String(edges[nbins])
            + "]"
        )

    var values = List[Float64](capacity=nbins)
    var running = 0.0
    for i in range(nbins):
        # The one line where `cumulative` differs: the mass being
        # normalized is the running total rather than this bin's own.
        running += mass[i]
        var v = running if cumulative else mass[i]
        # Width first, then total -- `numpy.histogram(density=True)`
        # evaluates `n / db / n.sum()` in that order, and reproducing it
        # operation for operation makes `DENSITY` agree with numpy in
        # every bit rather than in the last one or two.
        #
        # Cumulative output is already a mass, so the width division
        # that turns a mass into a per-unit-of-x rate does not apply:
        # the running total of a density is a CDF, which is unitless.
        if stat._normalizes_by_width() and not cumulative:
            v /= edges[i + 1] - edges[i]
        if stat._normalizes_by_total():
            v /= total
            if stat == HistStat.PERCENT:
                v *= 100.0
        values.append(v)

    return HistogramBins(edges.copy(), values^)


struct _HistogramLabels(Movable):
    """One bin-range label plus count per bin, in bin order: the
    `(x_categories, y_data)` pair `Plot.encode_histogram()` assigns once
    `_bin_histogram()` returns.
    """

    var labels: List[String]
    var counts: List[Float64]

    def __init__(out self, var labels: List[String], var counts: List[Float64]):
        """Construct from already-computed columns.

        Args:
            labels: One formatted range per bin.
            counts: One count per bin.
        """
        self.labels = labels^
        self.counts = counts^


def _bin_histogram(data: List[Float64], bins: Int) raises -> _HistogramLabels:
    """`Plot.encode_histogram()`'s categorical view of `histogram_bins()`:
    the same counts, with each bin's numeric interval formatted to one
    decimal place as a category label.

    Kept as a thin wrapper rather than its own binning loop so there is
    one boundary rule in this module rather than two that can drift.
    Validates up front so its messages can name `encode_histogram()`
    -- the caller a user of this path actually typed -- instead of the
    engine underneath.

    Args:
        data: The raw values to bin.
        bins: How many equal-width intervals to divide `data`'s range
            into.

    Returns:
        A label and a count per bin.

    Raises:
        Error: `data` is empty, `bins` is not positive, or any value is
            `NaN`/infinite.
    """
    if len(data) == 0:
        raise Error("Plot.encode_histogram(): data must not be empty")
    if bins <= 0:
        raise Error(
            "Plot.encode_histogram(): bins must be positive (got "
            + String(bins)
            + ")"
        )

    var binned = histogram_bins(data, bin_edges(data, bins))
    var labels = List[String](capacity=bins)
    for i in range(bins):
        labels.append(
            _format_fixed(binned.edges[i], 1)
            + "-"
            + _format_fixed(binned.edges[i + 1], 1)
        )
    return _HistogramLabels(labels^, binned.values.copy())


def histogram(
    data: List[Float64],
    bins: Int = 10,
    edges: List[Float64] = List[Float64](),
    weights: List[Float64] = List[Float64](),
    stat: HistStat = HistStat.COUNT,
    cumulative: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A histogram: continuous data grouped into bins and drawn as bar
    heights over a **numeric** x-axis, for showing a distribution's
    shape (its center, spread, and skew) rather than each individual
    value.

    The chart uses a filled `StepStyle.POST` area over the bin edges and
    pins the x-domain to the first and last edge. For categorical range
    labels, use `Plot().mark_bar().encode_histogram(...)` instead.

    The pinned x-domain has one cost worth knowing before building on
    it: `render_layers()` refuses any layer carrying an explicit domain
    , so a `histogram()` cannot yet be *overlaid* on anything.
    `render_facets()`/`save_facets()` has no such restriction, and two
    histograms sharing `edges` line up bar for bar across panels --
    identical edges give identical domains -- which is what the "Shared
    Bins" example below draws.

    Args:
        data: The raw values to bin -- not pre-counted; binning
            happens internally.
        bins: How many equal-width intervals to divide `data`'s range
            into. Ignored when `edges` is given.
        edges: Explicit bin boundaries, strictly ascending, at least 2
            long -- for unequal widths, for a fixed range that does not
            follow the data (`uniform_bin_edges(0.0, 100.0, 20)`), or
            for two samples that must share intervals
            (`shared_bin_edges([a, b], bins=20)`). Empty (the default)
            derives `bins` equal intervals from `data`'s own range.
        weights: One nonnegative weight per observation, or empty (the
            default) for one apiece -- survey weights, dollar amounts,
            exposure times. A bin then holds the total weight that
            landed in it.
        stat: What a bar's height is: `HistStat.COUNT` (the default),
            `FREQUENCY`, `PROBABILITY`, `PERCENT`, or `DENSITY`. Use
            `DENSITY` or `FREQUENCY` with unequal-width `edges`, where a
            raw count makes a wide bin look like a tall one.
        cumulative: Draw each bin as the running total at or below its
            right edge, turning the chart into an empirical CDF.
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

    Raises:
        Error: `data` is empty, `bins` is not positive, `edges` is
            shorter than 2 or not strictly ascending, `weights` is
            neither empty nor one per observation, a weight is
            negative, or a value is `NaN`/infinite.

    Example:
        ```mojo
        from dataviz import histogram
        from dataviz.plot import save
        from dataviz.colors import REBECCAPURPLE
        from dataviz.theme import Theme

        def main() raises:
            # Exam scores out of 100 -- a real bell-ish spread, not a uniform
            # or already-sorted list, so the binning has genuine work to do.
            var scores: List[Int] = [
                52, 61, 65, 68, 70, 71, 72, 74, 75, 76,
                77, 78, 78, 79, 80, 81, 81, 82, 83, 84,
                85, 86, 87, 88, 89, 90, 91, 93, 95, 98,
            ]

            var c = histogram(
                scores,
                bins=8,
                theme=Theme(mark_color=REBECCAPURPLE),
                x_title="Score",
                y_title="Students",
            )
            save(c, "docs/src/examples/out_histogram.svg")
        ```

    Example (Shared Bins):
        ```mojo
        from dataviz import save_facets
        from dataviz.colors import CRIMSON, STEELBLUE
        from dataviz.histogram import HistStat, histogram, shared_bin_edges
        from dataviz.plot import Plot
        from dataviz.theme import Theme

        def main() raises:
            # Two production lines, same part, measured in microns off
            # nominal. Line B runs wider AND is shifted high; the only way
            # to see both facts at once is for the two histograms to use
            # the same intervals, so a bar in one covers exactly the bar
            # beside it.
            var line_a: List[Float64] = [
                -3.1, -2.4, -2.0, -1.6, -1.5, -1.1, -0.9, -0.8, -0.6, -0.4,
                -0.3, -0.2, 0.0, 0.1, 0.2, 0.4, 0.5, 0.7, 0.9, 1.2,
                1.4, 1.8, 2.2, 2.9,
            ]
            var line_b: List[Float64] = [
                -2.2, -1.3, -0.5, 0.1, 0.4, 0.8, 1.0, 1.3, 1.5, 1.7,
                1.9, 2.0, 2.2, 2.4, 2.6, 2.8, 3.1, 3.4, 3.8, 4.3,
                4.9, 5.6, 6.4, 7.5,
            ]

            # One call, both samples: the pooled min and max in 12 equal
            # intervals. Binning each sample on its own range would give
            # the two charts different bars.
            var groups: List[List[Float64]] = [line_a.copy(), line_b.copy()]
            var edges = shared_bin_edges(groups, bins=12)

            # PROBABILITY, not COUNT, so the two panels are comparable
            # even when the samples are not the same size.
            var a = histogram(
                line_a,
                edges=edges,
                stat=HistStat.PROBABILITY,
                theme=Theme(mark_color=STEELBLUE, show_gridlines=False),
                width=380,
                height=320,
                title="Line A",
                x_title="Microns off nominal",
                y_title="Share of parts",
            )
            var b = histogram(
                line_b,
                edges=edges,
                stat=HistStat.PROBABILITY,
                theme=Theme(mark_color=CRIMSON, show_gridlines=False),
                width=380,
                height=320,
                title="Line B",
                x_title="Microns off nominal",
            )

            # Two panels rather than one overlay: render_layers() refuses
            # the explicit x-domain a histogram pins. The panels
            # still line up bar for bar, because the edges -- and so both
            # x-domains -- are the same list. Their y-axes are separate,
            # though, so read the bar positions across panels and
            # the heights within one.
            var panels: List[Plot] = [a^, b^]
            save_facets(panels, 2, "docs/src/examples/out_histogram_shared.svg")
        ```
    """
    var resolved = edges.copy() if len(edges) > 0 else bin_edges(data, bins)
    var binned = histogram_bins(
        data, resolved, weights=weights, stat=stat, cumulative=cumulative
    )
    var lo = binned.edges[0]
    var hi = binned.edges[len(binned.edges) - 1]
    # The x-domain is the bin range itself, not `_data_extent`'s 5% pad
    # around it: the leftmost and rightmost bars are meant to sit on the
    # axis ends, and padding would leave a strip of empty axis that
    # reads as "no observations here" when the truth is "no bins here".
    var plot = (
        Plot()
        .mark_area(step=StepStyle.POST)
        .encode(x=binned.step_x(), y=binned.step_y())
        .scale_x_domain(lo, hi)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def histogram[
    dtype: DType
](
    data: List[Scalar[dtype]],
    bins: Int = 10,
    edges: List[Float64] = List[Float64](),
    weights: List[Float64] = List[Float64](),
    stat: HistStat = HistStat.COUNT,
    cumulative: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`histogram()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (continuous.mojo). Delegates to the concrete overload
    above.

    `edges` and `weights` stay `List[Float64]` rather than following
    `dtype`: they are axis positions and multipliers, not observations,
    and a caller with `List[Int32]` samples still wants a bin boundary
    at 2.5.

    Parameters:
        dtype: The element type of `data`.

    Args:
        data: The raw values to bin.
        bins: How many equal-width intervals to divide `data`'s range into.
        edges: Explicit bin boundaries; empty derives them from `data`.
        weights: One nonnegative weight per observation, or empty.
        stat: What a bar's height is; see `HistStat`.
        cumulative: Draw running totals instead of per-bin values.
        theme: Full styling knobs -- see `Theme`'s docstring.
        width: Pixel width of the returned `Plot`.
        height: Pixel height of the returned `Plot`.
        title: The chart's title.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: Whatever the concrete overload raises.
    """
    return histogram(
        _materialize_scalar_list(data),
        bins=bins,
        edges=edges,
        weights=weights,
        stat=stat,
        cumulative=cumulative,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
