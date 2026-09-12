"""`Mark.HIST2D` and `hist2d()`: a 2D histogram -- continuous `(x, y)`
points binned into a rectangular grid of counts, drawn as colored
cells, so a point cloud too dense to read as a scatter shows where it
concentrates."""

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.histogram import BinRule, _bin_index, bin_edges
from dataviz.plot import Plot, _finished
from dataviz.core.theme import Theme


def _hist2d_counts(
    x: List[Float64],
    y: List[Float64],
    x_edges: List[Float64],
    y_edges: List[Float64],
) raises -> List[List[Float64]]:
    """Count the `(x, y)` pairs in every cell of the grid `x_edges` by
    `y_edges` bound.

    Row-major, `counts[row][col]` for the cell between `y_edges[row]`
    and `y_edges[row + 1]` and between `x_edges[col]` and
    `x_edges[col + 1]`: the shape `encode_pcolormesh()` takes, so a row
    is a band of y and row 0 sits at the bottom of the chart.

    Each axis is binned by `_bin_index`, the 1D histogram's rule: a bin
    is closed on the left and open on the right, except the last, which
    is closed on both ends so the sample maximum lands inside the
    histogram. A point on a shared boundary therefore goes to the upper
    bin, on both axes, and that is pinned by a test because it is where
    implementations quietly differ. A point outside the edges on either
    axis is not counted at all, as numpy's `histogram2d` drops it.

    Args:
        x: The horizontal coordinates.
        y: The vertical coordinates, one per `x`.
        x_edges: Column boundaries, strictly increasing, at least 2.
        y_edges: Row boundaries, strictly increasing, at least 2.

    Returns:
        `len(y_edges) - 1` rows of `len(x_edges) - 1` counts.

    Raises:
        Error: `x` and `y` differ in length, or either edge list is
            shorter than 2.
    """
    if len(x) != len(y):
        raise Error(
            "hist2d(): x and y must be the same length -- got "
            + String(len(x))
            + " x values and "
            + String(len(y))
            + " y values"
        )
    if len(x_edges) < 2 or len(y_edges) < 2:
        raise Error(
            "hist2d(): each axis needs at least one bin (two edges) -- got "
            + String(len(x_edges))
            + " x edges and "
            + String(len(y_edges))
            + " y edges"
        )
    var cols = len(x_edges) - 1
    var rows = len(y_edges) - 1
    var counts = List[List[Float64]](capacity=rows)
    for _ in range(rows):
        var row = List[Float64](capacity=cols)
        for _ in range(cols):
            row.append(0.0)
        counts.append(row^)
    for i in range(len(x)):
        var c = _bin_index(x[i], x_edges)
        if c < 0:
            continue
        var r = _bin_index(y[i], y_edges)
        if r < 0:
            continue
        counts[r][c] += 1.0
    return counts^


def _hist2d_plot(
    x: List[Float64],
    y: List[Float64],
    x_edges: List[Float64],
    y_edges: List[Float64],
    theme: Theme,
    width: Int,
    height: Int,
    title: String,
    subtitle: String,
    x_title: String,
    y_title: String,
) raises -> Plot:
    var plot = Plot().mark_hist2d().encode_hist2d(x, y, x_edges, y_edges)
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def hist2d(
    x: List[Float64],
    y: List[Float64],
    bins: Int,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A 2D histogram, matplotlib's `hist2d()`: `(x, y)` points binned
    into a `bins` by `bins` grid of equal-width cells over each axis's
    own range, each cell colored by how many points fell in it.

    This is the chart for a point cloud too dense to read as a scatter:
    fifty thousand points are a solid blob, and binning them is what
    shows where they concentrate. `Mark.HEATMAP` displays a grid
    someone else computed; this computes one from points.

    Cells no point fell in are left as background, not painted the
    bottom of the ramp. A zero-count cell is "nothing here", and the
    lowest color would claim a measurement. Counted cells run from the
    bottom of the theme's ramp at zero to its top at the fullest cell,
    with the color legend reading in counts. The eye reads apparent
    structure into an uneven lightness ramp, so this is the chart type
    where a perceptual colormap (`Theme(color_ramp=viridis())`) matters
    most.

    `bins` counts bins per axis; the grid is always square in bin
    count, as matplotlib's integer `bins` is. For bins chosen by a rule
    from the data, see the overload that takes a `BinRule`, which is
    also what the no-argument default does. To bin one axis differently
    from the other, build the plot by hand: `Plot().mark_hist2d()
    .encode_hist2d(x, y, x_edges, y_edges)` takes any edges.

    Args:
        x: The horizontal coordinates.
        y: The vertical coordinates, one per `x`.
        bins: Bins per axis, at least 1.
        theme: Visual theme.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Text under the title.
        x_title: Horizontal axis label.
        y_title: Vertical axis label.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Raises:
        Error: `x` and `y` differ in length or are empty, `bins` is
            below 1, or an axis has no range to bin.

    Example:
        ```mojo
        from dataviz import hist2d, save
        from dataviz import Theme
        from dataviz.core.colormaps import viridis

        def main() raises:
            # Twenty thousand sensor readings that fall in two clusters,
            # one tight and one spread out; as a scatter they would be a
            # blob. A small linear congruential generator keeps the
            # example self-contained.
            var seed = 12345
            var xs = List[Float64]()
            var ys = List[Float64]()
            for i in range(20000):
                var u = List[Float64]()
                for _ in range(6):
                    seed = (seed * 1103515245 + 12345) % 2147483648
                    u.append(Float64(seed % 10000) / 10000.0 - 0.5)
                # Sums of uniforms are bell-shaped, which is all the
                # example needs.
                var gx = u[0] + u[1] + u[2]
                var gy = u[3] + u[4] + u[5]
                if i % 3 == 0:
                    xs.append(2.0 + 0.6 * gx)
                    ys.append(7.0 + 0.6 * gy)
                else:
                    xs.append(6.0 + 2.2 * gx + 0.8 * gy)
                    ys.append(3.0 + 1.6 * gy)
            var chart = hist2d(
                xs,
                ys,
                bins=40,
                theme=Theme(color_ramp=viridis()),
                title="Illustrative Sensor Readings, Binned",
                x_title="Reading A",
                y_title="Reading B",
            )
            save(chart, "docs/src/examples/out_hist2d.svg")
        ```
    """
    if bins < 1:
        raise Error("hist2d(): bins must be at least 1 -- got " + String(bins))
    if len(x) != len(y):
        raise Error(
            "hist2d(): x and y must be the same length -- got "
            + String(len(x))
            + " x values and "
            + String(len(y))
            + " y values"
        )
    return _hist2d_plot(
        x,
        y,
        bin_edges(x, bins),
        bin_edges(y, bins),
        theme,
        width,
        height,
        title,
        subtitle,
        x_title,
        y_title,
    )


def hist2d(
    x: List[Float64],
    y: List[Float64],
    rule: BinRule = BinRule.AUTO,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`hist2d()` with the bins per axis chosen by `rule` from that
    axis's own data, the way `histogram()`'s rule overload chooses them
    -- so the x and y bin counts can differ. `BinRule.AUTO` is the
    default, as it is for `histogram()`.

    Args:
        x: The horizontal coordinates.
        y: The vertical coordinates, one per `x`.
        rule: How to pick each axis's bin count from its data.
        theme: Visual theme.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Text under the title.
        x_title: Horizontal axis label.
        y_title: Vertical axis label.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Raises:
        Error: `x` and `y` differ in length or are empty, or an axis
            has no range to bin.
    """
    if len(x) != len(y):
        raise Error(
            "hist2d(): x and y must be the same length -- got "
            + String(len(x))
            + " x values and "
            + String(len(y))
            + " y values"
        )
    return _hist2d_plot(
        x,
        y,
        bin_edges(x, rule),
        bin_edges(y, rule),
        theme,
        width,
        height,
        title,
        subtitle,
        x_title,
        y_title,
    )


def hist2d[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    bins: Int,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`hist2d()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (continuous.mojo). Delegates to the concrete overload
    above.

    Parameters:
        dtype: The element type of `x` and `y`.

    Args:
        x: The horizontal coordinates.
        y: The vertical coordinates, one per `x`.
        bins: Bins per axis, at least 1.
        theme: Visual theme.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Text under the title.
        x_title: Horizontal axis label.
        y_title: Vertical axis label.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: As the concrete overload.
    """
    return hist2d(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        bins,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )


def hist2d[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    rule: BinRule = BinRule.AUTO,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """The `BinRule` form of `hist2d()` generalized over numeric element
    type. Delegates to the concrete overload above.

    Parameters:
        dtype: The element type of `x` and `y`.

    Args:
        x: The horizontal coordinates.
        y: The vertical coordinates, one per `x`.
        rule: How to pick each axis's bin count from its data.
        theme: Visual theme.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Text under the title.
        x_title: Horizontal axis label.
        y_title: Vertical axis label.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: As the concrete overload.
    """
    return hist2d(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        rule,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
