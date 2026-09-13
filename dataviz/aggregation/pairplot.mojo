"""Every numeric variable against every other, in one grid (#353).

seaborn's `pairplot`, and the first thing many people run on a new
dataset, because it answers "what is related to what" in one figure.

This is composition, not a new mark. Cell `(i, j)` is a scatter of
variable `j` against variable `i`, the diagonal is variable `i`'s own
distribution, and the whole thing goes through `render_facets()`.

What makes it a pairplot rather than a grid of unrelated charts is the
scales. Column `j` shares one x-domain down its whole height and row `i`
shares one y-domain across its whole width, both pinned from the
variable's own range. Without that the cells are not comparable and the
figure lies: two panels of the same variable would draw it at two
different widths and a reader would read the difference as data.

`Mark.CORRPLOT` answers a related question and is not a substitute. A
correlation of 0.0 looks the same for independent data and for a perfect
parabola; the scatter is where you see which one you have.
"""

from canvas.buffer import Canvas

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.scale import MinMax
from dataviz.core.theme import Theme
from dataviz.binned.histogram import bin_edges, histogram_bins
from dataviz.facets import render_facets
from dataviz.plot import Plot


def _column_extent(values: List[Float64]) raises -> MinMax:
    """One variable's own range, padded so points do not sit on the frame.

    The padding matches what a standalone scatter would apply, so a cell
    of a pairplot and the same data plotted alone put their points in the
    same place.

    Args:
        values: The column.

    Returns:
        The padded `[min, max]`.

    Raises:
        Error: The column is empty.
    """
    if len(values) == 0:
        raise Error("pairplot(): a variable has no values")
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


def pairplot[
    dtype: DType
](
    columns: List[List[Scalar[dtype]]],
    names: List[String],
    theme: Theme = Theme(),
    cell_width: Int = 220,
    cell_height: Int = 180,
    bins: Int = 10,
) raises -> Canvas:
    """Every variable against every other, with distributions down the
    diagonal (#353).

    Returns a rendered `Canvas` rather than a `Plot`, because a pairplot
    is a *figure* of n-squared panels and `Plot` is one chart. That is
    the same reason `render_facets()` returns a canvas.

    Column `j` shares one x-domain and row `i` shares one y-domain, both
    taken from the variable's own padded range, so every panel showing a
    variable draws it at the same scale. A grid of independently scaled
    cells would look identical and mean something else.

    The diagonal uses `Mark.HISTOGRAM` rather than a bar chart of bin
    labels, because that one draws its rectangles at numeric x positions
    and so lines up with the scatter panels in its column. A bar chart's
    categorical axis would not.

    The diagonal is variable `i`'s histogram. Its y-axis is a count and
    therefore does not share the row's domain, which is the one place
    the grid's scale rule deliberately does not apply; seaborn does the
    same.

    Args:
        columns: One list per variable, all the same length.
        names: One label per variable, used as each panel's axis title.
        theme: Applied to every panel.
        cell_width: Each panel's width in pixels.
        cell_height: Each panel's height.
        bins: Histogram bins on the diagonal.

    Returns:
        The rendered figure, `len(columns)` panels across.

    Raises:
        Error: Fewer than two variables, a name count that does not match,
            columns of differing length, or an empty column.
    """
    var n = len(columns)
    if n < 2:
        raise Error(
            "pairplot(): needs at least two variables to pair -- got "
            + String(n)
        )
    if len(names) != n:
        raise Error(
            "pairplot(): one name per variable, so "
            + String(n)
            + " -- got "
            + String(len(names))
        )

    var cols = List[List[Float64]](capacity=n)
    for i in range(n):
        cols.append(_materialize_scalar_list(columns[i]))
    for i in range(1, n):
        if len(cols[i]) != len(cols[0]):
            raise Error(
                "pairplot(): every variable needs the same number of rows -- '"
                + names[0]
                + "' has "
                + String(len(cols[0]))
                + " and '"
                + names[i]
                + "' has "
                + String(len(cols[i]))
            )

    var extents = List[MinMax](capacity=n)
    for i in range(n):
        extents.append(_column_extent(cols[i]))

    var plots = List[Plot](capacity=n * n)
    for i in range(n):
        for j in range(n):
            if i == j:
                # The distribution of one variable. Its x-domain is still
                # the column's, so the diagonal lines up with the scatter
                # panels above and below it.
                plots.append(
                    Plot()
                    .mark_histogram()
                    .encode_histogram_bins(
                        histogram_bins(cols[i], bin_edges(cols[i], bins))
                    )
                    .scale_x_domain(extents[i].min, extents[i].max)
                    .theme(theme)
                    .size(cell_width, cell_height)
                    .labels(x_title=names[i], y_title="count")
                )
            else:
                plots.append(
                    Plot()
                    .mark_point()
                    .encode(x=cols[j], y=cols[i])
                    .scale_x_domain(extents[j].min, extents[j].max)
                    .scale_y_domain(extents[i].min, extents[i].max)
                    .theme(theme)
                    .size(cell_width, cell_height)
                    .labels(x_title=names[j], y_title=names[i])
                )
    return render_facets(plots, n)
