"""A bivariate chart with each variable's own distribution beside it (#354).

A scatter of `y` against `x`, a histogram of `x` along the top, and a
histogram of `y` down the right side.

It is the natural chart for "are these two related, and what does each
look like on its own", and the answer is often that a convincing-looking
correlation is driven by a bimodal marginal the scatter alone does not
show.

**The layout is the feature.** A marginal has to sit over the panel it
describes: a value at the main panel's pixel `p` must appear at pixel
`p` in the strip above it, or the figure is telling you the mass is
somewhere it is not. Two things make that true here, and neither is
free.

The domains are pinned. Each marginal takes its bin range from the main
panel's own padded extent rather than from its own data, so the strip
covers exactly the span the scatter does.

The pixels are aligned. Equal domains are not enough: each cell sizes
its margins from its own tick labels, and a marginal counts observations
while the panel shows the data, so their labels differ in width and
their plot rects would start at different pixels. `render_grid`'s
`align_axes` measures every cell and puts a column on one pair of
vertical edges (#569). That is the piece this chart was waiting on.

The corner opposite the two marginals is left empty and takes the figure background rather than showing through.
"""


from dataframe import DataFrame

from dataviz.binned.histogram import bin_edges, histogram_bins
from dataviz.core.frame_input import _frame_floats
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.scale import MinMax
from dataviz.core.theme import Theme

from dataviz.layout import Figure, GridCell
from dataviz.chart import AnyChart
from dataviz.plot import Plot


def _padded_extent(values: List[Float64], axis: String) raises -> MinMax:
    """One variable's range with the 5% padding a scatter applies.

    Taken from the data rather than from the rendered scatter because
    the marginals need it before anything is drawn, and it has to be the
    same number the panel will use or the strip will not line up.

    Args:
        values: The column.
        axis: Which one, for the error message.

    Returns:
        The padded `[min, max]`.

    Raises:
        Error: The column is empty.
    """
    if len(values) == 0:
        raise Error("jointplot(): " + axis + " has no values")
    var lo = values[0]
    var hi = values[0]
    for v in values:
        if v < lo:
            lo = v
        if v > hi:
            hi = v
    var span = hi - lo
    var pad = span * 0.05 if span > 0.0 else 1.0
    return MinMax(lo - pad, hi + pad)


def _even_edges(lo: Float64, hi: Float64, bins: Int) raises -> List[Float64]:
    """`bins` equal intervals spanning exactly `[lo, hi]`.

    Not `bin_edges()`, which picks a range from the data. A marginal's
    range is the main panel's, so that the two line up; letting the
    histogram choose its own would undo the alignment this chart exists
    for.

    Args:
        lo: The low end, inclusive.
        hi: The high end, inclusive.
        bins: How many intervals.

    Returns:
        `bins + 1` edges.

    Raises:
        Error: A non-positive bin count.
    """
    if bins <= 0:
        raise Error(
            "jointplot(): bins must be positive (got " + String(bins) + ")"
        )
    var edges = List[Float64](capacity=bins + 1)
    for i in range(bins + 1):
        edges.append(lo + (hi - lo) * Float64(i) / Float64(bins))
    return edges^


def _jointplot_panels[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    theme: Theme,
    width: Int,
    height: Int,
    bins: Int,
    ratio: Float64,
    title: String,
    x_title: String,
    y_title: String,
    mut plots: List[AnyChart],
    mut cells: List[GridCell],
) raises:
    """The three panels `jointplot()` lays out and where each goes,
    built once for both the raster and the vector form (#620).

    Everything that decides what the figure says -- the shared domains,
    the two marginals\' bin edges, which panel carries the title -- is
    here; `jointplot()` only wraps the result in a `Figure`, and every
    export format draws that one figure.

    Args:
        x: The horizontal variable.
        y: The vertical variable.
        theme: Colors and fonts, shared by all three panels.
        width: Figure width.
        height: Figure height.
        bins: Intervals in each marginal.
        ratio: How many times a marginal\'s size the main panel is.
        title: Shown above the top marginal.
        x_title: The horizontal axis caption.
        y_title: The vertical axis caption.
        plots: Filled with the three panels.
        cells: Filled with where each one goes.

    Raises:
        Error: Empty or mismatched columns, a non-positive `bins`, or a
            `ratio` that is not above zero.
    """
    var xs = _materialize_scalar_list(x)
    var ys = _materialize_scalar_list(y)
    if len(xs) == 0:
        raise Error("jointplot(): x has no values")
    if len(xs) != len(ys):
        raise Error(
            "jointplot(): x and y must be the same length -- got "
            + String(len(xs))
            + " and "
            + String(len(ys))
        )
    if ratio <= 0.0:
        raise Error(
            "jointplot(): ratio must be above zero (got " + String(ratio) + ")"
        )

    var x_extent = _padded_extent(xs, "x")
    var y_extent = _padded_extent(ys, "y")

    # The main panel. Its domains are pinned rather than left to
    # _data_extent, so the marginals can be pinned to the same numbers.
    var main = (
        Plot()
        .mark_point()
        .encode(x=xs, y=ys)
        .scale_x_domain(x_extent.min, x_extent.max)
        .scale_y_domain(y_extent.min, y_extent.max)
        .labels(x_title=x_title, y_title=y_title)
        .theme(theme)
        .size(width, height)
    )

    # The top strip: x's distribution over exactly the panel's x-range.
    var top_edges = _even_edges(x_extent.min, x_extent.max, bins)
    var top = (
        Plot()
        .mark_histogram()
        .encode_histogram_bins(histogram_bins(xs, top_edges))
        .scale_x_domain(x_extent.min, x_extent.max)
        .labels(title=title)
        .theme(theme)
        .size(width, height)
    )

    # The right strip: y's distribution, bins running up the y-axis and
    # counts running right, which is what horizontal=True is for.
    var right_edges = _even_edges(y_extent.min, y_extent.max, bins)
    var right = (
        Plot()
        .mark_histogram(horizontal=True)
        .encode_histogram_bins(histogram_bins(ys, right_edges))
        .scale_y_domain(y_extent.min, y_extent.max)
        .theme(theme)
        .size(width, height)
    )

    # Top-left is the x marginal, bottom-left the panel, bottom-right the
    # y marginal. Top-right stays empty, as seaborn leaves it.
    plots.append(AnyChart(top))
    plots.append(AnyChart(main))
    plots.append(AnyChart(right))
    cells.append(GridCell(0, 0))
    cells.append(GridCell(1, 0))
    cells.append(GridCell(1, 1))


def _jointplot_weights(
    ratio: Float64, mut rows: List[Float64], mut cols: List[Float64]
):
    """The grid's track weights: a marginal, then the main panel at
    `ratio` times its size, down and across.

    Args:
        ratio: How many times a marginal's size the main panel is.
        rows: Filled with the row weights.
        cols: Filled with the column weights.
    """
    rows.append(1.0)
    rows.append(ratio)
    cols.append(ratio)
    cols.append(1.0)


def jointplot(
    df: DataFrame,
    x: String,
    y: String,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 640,
    bins: Int = 20,
    ratio: Float64 = 4.0,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Figure:
    """Make a jointplot from two named numeric DataFrame columns (#743).

    Args:
        df: The frame containing both variables.
        x: Name of the horizontal numeric column.
        y: Name of the vertical numeric column.
        theme: Figure styling and missing-value policy.
        width: Figure width in pixels.
        height: Figure height in pixels.
        bins: Number of marginal histogram bins.
        ratio: Main panel size relative to its marginals.
        title: Figure title.
        x_title: Horizontal title, defaulting to `x`.
        y_title: Vertical title, defaulting to `y`.

    Returns:
        The unrendered figure.

    Raises:
        Error: A named column is absent, nonnumeric, or has missing
            values under the default missing-value policy.
    """
    var xs = _frame_floats(df, x, "jointplot()", theme.missing)
    var ys = _frame_floats(df, y, "jointplot()", theme.missing)
    return jointplot(
        xs,
        ys,
        theme=theme,
        width=width,
        height=height,
        bins=bins,
        ratio=ratio,
        title=title,
        x_title=x_title if x_title.byte_length() > 0 else x,
        y_title=y_title if y_title.byte_length() > 0 else y,
    )


def jointplot[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 640,
    bins: Int = 20,
    ratio: Float64 = 4.0,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Figure:
    """A scatter of `y` against `x` with each variable's distribution
    along its own axis.

    Returns a `Figure` rather than a `Plot`, because the result is
    several charts in a grid and a `Plot` is one chart. Like a `Plot`,
    it is not rendered until it is exported: `save()`, `render()`,
    `render_svg()` and `render_pdf()` all take it (#697).

    Example:
        ```mojo
        from dataviz import jointplot, save

        def main() raises:
            # A correlated pair from a fixed linear congruential sequence,
            # so the figure is the same on every run.
            var x = List[Float64]()
            var y = List[Float64]()
            var seed = 20260913
            for _ in range(400):
                seed = (seed * 1103515245 + 12345) % 2147483648
                var a = Float64(seed % 10000) / 1000.0
                seed = (seed * 1103515245 + 12345) % 2147483648
                var b = Float64(seed % 10000) / 1000.0
                x.append(a)
                y.append(a * 0.6 + b * 0.4)
            var c = jointplot(
                x,
                y,
                title="Joint distribution",
                x_title="x",
                y_title="0.6 x + noise",
            )
            save(c, "docs/src/examples/out_jointplot.svg")
        ```

    Args:
        x: The horizontal variable.
        y: The vertical variable, one per `x` entry.
        theme: Colors and fonts, shared by all three panels.
        width: Figure width in pixels.
        height: Figure height in pixels.
        bins: Intervals in each marginal.
        ratio: How many times the main panel's size the marginals are
            divided into. At the default of 4 a marginal is a fifth of
            the figure.
        title: Shown above the top marginal, which is the top of the
            figure.
        x_title: The horizontal axis caption, on the main panel.
        y_title: The vertical axis caption, on the main panel.

    Returns:
        The unrendered figure.

    Raises:
        Error: Empty or mismatched columns, a non-positive `bins`, or a
            `ratio` that is not above zero.
    """
    var plots = List[AnyChart]()
    var cells = List[GridCell]()
    _jointplot_panels(
        x,
        y,
        theme,
        width,
        height,
        bins,
        ratio,
        title,
        x_title,
        y_title,
        plots,
        cells,
    )
    var rows = List[Float64]()
    var cols = List[Float64]()
    _jointplot_weights(ratio, rows, cols)
    return Figure(
        plots^,
        cells^,
        width,
        height,
        row_weights=rows^,
        col_weights=cols^,
        align_axes=True,
    )
