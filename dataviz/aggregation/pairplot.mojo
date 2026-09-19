"""Every numeric variable against every other, in one grid (#353).

The first thing many people run on a new dataset, because it answers
"what is related to what" in one figure.

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


from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.scale import MinMax
from dataviz.core.theme import Theme
from dataviz.binned.histogram import bin_edges, histogram_bins

from dataviz.facets import _facets_figure
from dataviz.layout import Figure
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


def _pairplot_panels[
    dtype: DType
](
    columns: List[List[Scalar[dtype]]],
    names: List[String],
    theme: Theme,
    cell_width: Int,
    cell_height: Int,
    bins: Int,
) raises -> List[Plot]:
    """The n-squared panels `pairplot()` lays out, built once for both
    the raster and the vector form (#620).

    Everything that decides what the figure *says* -- the shared
    domains, the histogram diagonal, the panel titles -- is here;
    `pairplot()` only wraps the result in a `Figure`, and every export
    format draws that one figure.

    Args:
        columns: One list per variable.
        names: One label per variable.
        theme: Applied to every panel.
        cell_width: Each panel's width.
        cell_height: Each panel's height.
        bins: Histogram bins on the diagonal.

    Returns:
        The panels, row-major.

    Raises:
        Error: Fewer than two variables, a name count that does not
            match, columns of differing length, or an empty column.
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
    return plots^


def pairplot[
    dtype: DType
](
    columns: List[List[Scalar[dtype]]],
    names: List[String],
    theme: Theme = Theme(),
    cell_width: Int = 220,
    cell_height: Int = 180,
    bins: Int = 10,
    title: String = "",
) raises -> Figure:
    """Every variable against every other, with distributions down the
    diagonal (#353).

    Returns a `Figure` rather than a `Plot`, because the result is
    several charts in a grid and a `Plot` is one chart. Like a `Plot`,
    it is not rendered until it is exported: `save()`, `render()`,
    `render_svg()` and `render_pdf()` all take it (#697).

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
    the grid's scale rule deliberately does not apply.

    Example:
        ```mojo
        from dataviz import pairplot, save

        def main() raises:
            # Illustrative measurements for a dozen sedans: engine size
            # in liters, horsepower, and highway miles per gallon.
            var columns: List[List[Float64]] = [
                [1.5, 1.6, 1.8, 2.0, 2.0, 2.4, 2.5, 3.0, 3.3, 3.5, 4.0, 4.4],
                [118, 132, 140, 158, 170, 185, 203, 255, 268, 290, 335, 375],
                [38, 36, 34, 31, 30, 28, 27, 24, 23, 21, 19, 17],
            ]
            var c = pairplot(
                columns,
                ["Engine (L)", "Horsepower", "MPG"],
                title="Sedan specifications, pairwise",
            )
            save(c, "docs/src/examples/out_pairplot.svg")
        ```

    Args:
        columns: One list per variable, all the same length.
        names: One label per variable, used as each panel's axis title.
        theme: Applied to every panel.
        cell_width: Each panel's width in pixels.
        cell_height: Each panel's height.
        bins: Histogram bins on the diagonal.
        title: A figure title above the whole grid; the figure grows by
            the title's band so the panels keep `cell_height`. Empty
            for none.

    Returns:
        The unrendered figure, `len(columns)` panels across.

    Raises:
        Error: Fewer than two variables, a name count that does not match,
            columns of differing length, or an empty column.
    """
    return _facets_figure(
        _pairplot_panels(columns, names, theme, cell_width, cell_height, bins),
        len(columns),
        title=title,
    )
