"""`clustermap()`: a heatmap whose rows and columns are reordered by
hierarchical clustering, with the tree that did the reordering drawn
along each edge (#355).

The reordering is the whole feature. A matrix in the order it arrived
shows almost nothing; the same matrix with similar rows together shows
its block structure at a glance, and the dendrograms say how strongly
each block holds.

Composition, not a mark: three plots in a grid, the same way
`jointplot()` is a scatter with two marginals. `dataviz.core.cluster`
decides the order, `Mark.DENDROGRAM` draws the trees, `Mark.HEATMAP`
draws the matrix, and `render_grid(align_axes=True)` is what makes a
leaf sit over the column it names.
"""

from canvas.buffer import Canvas

from dataviz.core.cluster import DistanceMetric, Linkage, linkage
from dataviz.core.theme import Theme
from dataviz.grid.heatmap import heatmap
from canvas.vector.pdf import PdfCanvas
from canvas.vector.svg import SvgCanvas

from dataviz.layout import (
    GridCell,
    render_grid,
    render_grid_pdf,
    render_grid_svg,
)
from dataviz.plot import Plot


def _transpose(values: List[List[Float64]]) raises -> List[List[Float64]]:
    """`values` with rows and columns exchanged, so the same clustering
    code can order the columns.

    Args:
        values: The matrix, one list per row.

    Returns:
        The transpose.

    Raises:
        Error: The matrix is empty or ragged.
    """
    if len(values) == 0 or len(values[0]) == 0:
        raise Error("clustermap(): values must not be empty")
    var rows = len(values)
    var cols = len(values[0])
    var out = List[List[Float64]](capacity=cols)
    for c in range(cols):
        var column = List[Float64](capacity=rows)
        for r in range(rows):
            if len(values[r]) != cols:
                raise Error(
                    "clustermap(): every row needs the same number of"
                    " columns -- row 0 has "
                    + String(cols)
                    + " and row "
                    + String(r)
                    + " has "
                    + String(len(values[r]))
                )
            column.append(values[r][c])
        out.append(column^)
    return out^


def _identity_order(n: Int) -> List[Int]:
    """`0 .. n-1`, the order an unclustered axis keeps."""
    var out = List[Int](capacity=n)
    for i in range(n):
        out.append(i)
    return out^


def _blank(n: Int) -> List[String]:
    """`n` empty labels.

    A dendrogram panel draws no tick labels of its own: the heatmap
    beside it already names every row and column, and a second copy
    would print into the panel between them. The tree's shape is what
    the panel is there for.
    """
    var out = List[String](capacity=n)
    for _ in range(n):
        out.append("")
    return out^


def _clustermap_panels(
    values: List[List[Float64]],
    row_labels: List[String],
    col_labels: List[String],
    metric: DistanceMetric,
    method: Linkage,
    theme: Theme,
    ratio: Float64,
    cluster_rows: Bool,
    cluster_cols: Bool,
    mut plots: List[Plot],
    mut cells: List[GridCell],
    mut row_weights: List[Float64],
    mut col_weights: List[Float64],
) raises:
    """The panels a clustermap lays out and where each goes, built once
    for both the raster and the vector form (#620).

    Everything that decides what the figure says -- the two clusterings,
    the reordered matrix, which panels exist at all -- is here, so the
    two entry points differ only in which `render_grid` they hand the
    result to and cannot drift into drawing different figures.

    Args:
        values: The matrix, one list per row.
        row_labels: One name per row; empty numbers them.
        col_labels: One name per column; empty numbers them.
        metric: How far apart two rows are.
        method: How far apart two clusters are.
        theme: Applied to every panel.
        ratio: How many times a tree panel's size the matrix is.
        cluster_rows: Cluster and reorder the rows.
        cluster_cols: Cluster and reorder the columns.
        plots: Filled with the panels.
        cells: Filled with where each goes.
        row_weights: Filled with the row track weights.
        col_weights: Filled with the column track weights.

    Raises:
        Error: An empty or ragged matrix, a label count that does not
            match, or anything `linkage()` raises.
    """
    if len(values) == 0 or len(values[0]) == 0:
        raise Error("clustermap(): values must not be empty")
    var n_rows = len(values)
    var n_cols = len(values[0])
    if len(row_labels) > 0 and len(row_labels) != n_rows:
        raise Error(
            "clustermap(): one row label per row, so "
            + String(n_rows)
            + " -- got "
            + String(len(row_labels))
        )
    if len(col_labels) > 0 and len(col_labels) != n_cols:
        raise Error(
            "clustermap(): one column label per column, so "
            + String(n_cols)
            + " -- got "
            + String(len(col_labels))
        )
    if ratio <= 0.0:
        raise Error(
            "clustermap(): ratio must be above zero (got " + String(ratio) + ")"
        )

    var row_order = _identity_order(n_rows)
    var col_order = _identity_order(n_cols)
    var row_tree = Plot()
    var col_tree = Plot()
    if cluster_rows:
        var tree = linkage(values, metric, method)
        row_order = tree.leaf_order.copy()
        row_tree = (
            Plot()
            .mark_dendrogram(horizontal=True)
            .encode_dendrogram(tree, _blank(n_rows), horizontal=True)
            .theme(theme)
        )
    if cluster_cols:
        var tree = linkage(_transpose(values), metric, method)
        col_order = tree.leaf_order.copy()
        col_tree = (
            Plot()
            .mark_dendrogram()
            .encode_dendrogram(tree, _blank(n_cols))
            .theme(theme)
        )

    # The heatmap takes one x, one y and one value per cell, and orders
    # its axes by first appearance -- so emitting the cells in clustered
    # order is what puts the axes in clustered order.
    var xs = List[String](capacity=n_rows * n_cols)
    var ys = List[String](capacity=n_rows * n_cols)
    var vals = List[Float64](capacity=n_rows * n_cols)
    for r in range(n_rows):
        var source_row = row_order[r]
        for c in range(n_cols):
            var source_col = col_order[c]
            xs.append(
                col_labels[source_col] if len(col_labels)
                > 0 else String(source_col)
            )
            ys.append(
                row_labels[source_row] if len(row_labels)
                > 0 else String(source_row)
            )
            vals.append(values[source_row][source_col])
    # The color bar draws in the matrix panel's own right-hand column,
    # so it sits between the matrix and the row tree. Moving it under
    # the matrix would close that gap, and is not possible today:
    # Mark.HEATMAP's bar ignores Theme.legend_position (#618). Left as it
    # is rather than worked around, since the fix belongs there.
    var matrix = heatmap(xs, ys, vals, theme=theme)

    # The grid is the two trees and the matrix, with the corner between
    # them left empty; a tree nobody asked for costs its whole track
    # rather than an empty cell, so an unclustered axis drops the row or
    # column outright.
    #
    # The row tree goes to the *right* of the matrix, not the left. A
    # horizontal dendrogram puts its leaves at the low end of its
    # distance axis, which is its left edge, so on the left of the
    # matrix it would grow away from the rows it names and put its root
    # against them. On the right the leaves land against the matrix
    # where they belong, and the row names keep the left margin.
    var top = 1 if cluster_cols else 0
    if cluster_cols:
        plots.append(col_tree^)
        cells.append(GridCell(0, 0))
        row_weights.append(1.0)
    plots.append(matrix^)
    cells.append(GridCell(top, 0))
    row_weights.append(ratio)
    col_weights.append(ratio)
    if cluster_rows:
        plots.append(row_tree^)
        cells.append(GridCell(top, 1))
        col_weights.append(1.0)


def clustermap(
    values: List[List[Float64]],
    row_labels: List[String] = List[String](),
    col_labels: List[String] = List[String](),
    metric: DistanceMetric = DistanceMetric.EUCLIDEAN,
    method: Linkage = Linkage.AVERAGE,
    theme: Theme = Theme(),
    width: Int = 720,
    height: Int = 620,
    ratio: Float64 = 4.0,
    cluster_rows: Bool = True,
    cluster_cols: Bool = True,
    title: String = "",
) raises -> Canvas:
    """A heatmap with its rows and columns reordered by hierarchical
    clustering, and the merge tree drawn along each reordered edge
    (#355).

    Returns a rendered `Canvas` rather than a `Plot`, for the reason
    `jointplot()` does: the result is several charts in a grid, and a
    `Plot` is one chart.

    The column tree sits above the matrix and the row tree to its
    *right*, where a horizontal dendrogram's leaves land against the
    rows they name rather than its root doing so, and the row names keep
    the left margin. The color bar sits in the matrix panel's own legend
    column, between the matrix and the row tree, until #618 lets it move
    under the matrix. The panels carry no tick labels of their own: the
    matrix already names every row and column, and a second copy would
    print into the gap between them. `render_grid(align_axes=True)` puts
    each panel's plot rect on the matrix's, so a leaf sits over the
    column it named.

    Set `cluster_rows` or `cluster_cols` to `False` to keep that axis in
    the order it arrived, which is what a matrix with a meaningful
    order already -- time down one axis, say -- wants; its dendrogram
    panel is then dropped rather than drawn as a tree nobody asked for.

    Example:
        ```mojo
        from dataviz import clustermap_svg, save

        def main() raises:
            # Illustrative monthly rainfall for six places, in mm, two
            # of them wet-winter and the rest wet-summer.
            var values: List[List[Float64]] = [
                [80.0, 70.0, 65.0, 55.0, 45.0, 30.0],
                [75.0, 68.0, 60.0, 52.0, 40.0, 28.0],
                [10.0, 12.0, 18.0, 30.0, 55.0, 70.0],
                [12.0, 15.0, 20.0, 34.0, 58.0, 75.0],
                [14.0, 16.0, 22.0, 36.0, 60.0, 78.0],
                [78.0, 72.0, 62.0, 50.0, 42.0, 32.0],
            ]
            var places: List[String] = [
                "Porto",
                "Bilbao",
                "Perth",
                "Adelaide",
                "Cape Town",
                "Lisbon",
            ]
            var months: List[String] = [
                "Jan",
                "Mar",
                "May",
                "Jul",
                "Sep",
                "Nov",
            ]
            var c = clustermap_svg(
                values,
                places,
                months,
                title="Monthly rainfall, clustered",
            )
            save(c, "docs/src/examples/out_clustermap.svg")
        ```

    Args:
        values: The matrix, one list per row, every row the same length.
        row_labels: One name per row; empty numbers them.
        col_labels: One name per column; empty numbers them.
        metric: How far apart two rows (or columns) are.
        method: How far apart two clusters are.
        theme: Applied to every panel.
        width: Figure width in points.
        height: Figure height in points.
        ratio: How many times a dendrogram panel's size the heatmap is,
            so the default of 4 gives each tree a fifth of the figure.
        cluster_rows: Cluster and reorder the rows.
        cluster_cols: Cluster and reorder the columns.
        title: A figure title above the whole thing; the figure grows by
            the title's band so the panels keep their sizes. Empty for
            none.

    Returns:
        The rendered figure.

    Raises:
        Error: An empty or ragged matrix, a label count that does not
            match, fewer than two rows or columns when clustering that
            axis, a non-positive `ratio`, or anything `linkage()`
            raises.
    """
    var plots = List[Plot]()
    var cells = List[GridCell]()
    var row_weights = List[Float64]()
    var col_weights = List[Float64]()
    _clustermap_panels(
        values,
        row_labels,
        col_labels,
        metric,
        method,
        theme,
        ratio,
        cluster_rows,
        cluster_cols,
        plots,
        cells,
        row_weights,
        col_weights,
    )
    return render_grid(
        plots,
        cells,
        width,
        height,
        row_weights=row_weights,
        col_weights=col_weights,
        align_axes=True,
        title=title,
    )


def clustermap_svg(
    values: List[List[Float64]],
    row_labels: List[String] = List[String](),
    col_labels: List[String] = List[String](),
    metric: DistanceMetric = DistanceMetric.EUCLIDEAN,
    method: Linkage = Linkage.AVERAGE,
    theme: Theme = Theme(),
    width: Int = 720,
    height: Int = 620,
    ratio: Float64 = 4.0,
    cluster_rows: Bool = True,
    cluster_cols: Bool = True,
    title: String = "",
) raises -> SvgCanvas:
    """`clustermap()`'s vector counterpart, over the same panels (#620).

    Args:
        values: The matrix, one list per row, every row the same length.
        row_labels: One name per row; empty numbers them.
        col_labels: One name per column; empty numbers them.
        metric: How far apart two rows (or columns) are.
        method: How far apart two clusters are.
        theme: Applied to every panel.
        width: Figure width in points.
        height: Figure height in points.
        ratio: How many times a dendrogram panel's size the matrix is.
        cluster_rows: Cluster and reorder the rows.
        cluster_cols: Cluster and reorder the columns.
        title: A figure title above the whole thing.

    Returns:
        The rendered figure.

    Raises:
        Error: As `clustermap()`.
    """
    var plots = List[Plot]()
    var cells = List[GridCell]()
    var row_weights = List[Float64]()
    var col_weights = List[Float64]()
    _clustermap_panels(
        values,
        row_labels,
        col_labels,
        metric,
        method,
        theme,
        ratio,
        cluster_rows,
        cluster_cols,
        plots,
        cells,
        row_weights,
        col_weights,
    )
    return render_grid_svg(
        plots,
        cells,
        width,
        height,
        row_weights=row_weights,
        col_weights=col_weights,
        align_axes=True,
        title=title,
    )


def clustermap_pdf(
    values: List[List[Float64]],
    row_labels: List[String] = List[String](),
    col_labels: List[String] = List[String](),
    metric: DistanceMetric = DistanceMetric.EUCLIDEAN,
    method: Linkage = Linkage.AVERAGE,
    theme: Theme = Theme(),
    width: Int = 720,
    height: Int = 620,
    ratio: Float64 = 4.0,
    cluster_rows: Bool = True,
    cluster_cols: Bool = True,
    title: String = "",
) raises -> PdfCanvas:
    """`clustermap()`'s one-page PDF counterpart, over the same
    panels (#372).

    One layout unit is one PDF point, 1/72 inch, so `width` by
    `height` is the page: a 640 by 640 figure is 8.89 inches square.
    Paths stay paths and text stays text, embedded as a font subset,
    so a panel's labels are selectable rather than a picture of
    themselves.

    Args:
        values: The matrix, one list per row, every row the same length.
        row_labels: One name per row; empty numbers them.
        col_labels: One name per column; empty numbers them.
        metric: How far apart two rows (or columns) are.
        method: How far apart two clusters are.
        theme: Applied to every panel.
        width: Figure width in points.
        height: Figure height in points.
        ratio: How many times a dendrogram panel's size the matrix is.
        cluster_rows: Cluster and reorder the rows.
        cluster_cols: Cluster and reorder the columns.
        title: A figure title above the whole thing.

    Returns:
        The rendered figure.

    Raises:
        Error: As `clustermap()`.
    """
    var plots = List[Plot]()
    var cells = List[GridCell]()
    var row_weights = List[Float64]()
    var col_weights = List[Float64]()
    _clustermap_panels(
        values,
        row_labels,
        col_labels,
        metric,
        method,
        theme,
        ratio,
        cluster_rows,
        cluster_cols,
        plots,
        cells,
        row_weights,
        col_weights,
    )
    return render_grid_pdf(
        plots,
        cells,
        width,
        height,
        row_weights=row_weights,
        col_weights=col_weights,
        align_axes=True,
        title=title,
    )
