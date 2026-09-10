"""Render 2D numeric arrays as colored cells.

`Mark.IMSHOW` uses a regular continuous grid; `Mark.PCOLORMESH` accepts
explicit cell edges. Unlike categorical `Mark.HEATMAP`, neither mark
draws category labels.
"""

from std.utils.numerics import isfinite

from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import ColorScale
from dataviz.mark import Mark
from dataviz.pixel_snap import _snap_pixel_edge
from dataviz.plot import (
    Plot,
    _LegendLayout,
    _RenderResult,
    _Scaled,
    _draw_continuous_axis_frame,
    _draw_continuous_color_legend,
    _dynamic_legend_width,
    _finished,
)
from dataviz.scale import LinearScale, _format_fixed
from dataviz.theme import Theme


struct _ImageData(Copyable, Movable):
    """The array `Mark.IMSHOW`/`Mark.PCOLORMESH` display, plus the cell
    edges `PCOLORMESH` needs. See `encode_imshow()`/`encode_pcolormesh()`.
    Stored on `Plot._image`.

    `z` is row-major (`z[row][col]`), every row the same length. Rows are
    the y axis and columns the x axis for both marks; what differs is
    where the cell boundaries come from and which way the y-axis counts.

    `x_edges`/`y_edges` are empty for `IMSHOW`, which puts cell centers
    at the integers `0 .. cols - 1` and so needs no coordinates of its
    own. For `PCOLORMESH` they are the cell *boundaries*, so there is
    one more of each than there are columns/rows -- the same
    `len(X) == cols + 1` rule matplotlib's `pcolormesh` uses for 1D
    coordinates.
    """

    var z: List[List[Float64]]
    var x_edges: List[Float64]
    var y_edges: List[Float64]

    def __init__(out self):
        self.z = List[List[Float64]]()
        self.x_edges = List[Float64]()
        self.y_edges = List[Float64]()


def _image_grid_shape(
    z: List[List[Float64]], mark: Mark
) raises -> Tuple[Int, Int]:
    """`z`'s (rows, cols), raising unless it is a non-empty rectangular
    grid.

    One row or one column is fine, unlike `contour.mojo`'s `_grid_shape`,
    which needs 2x2 because marching squares walks the cells *between*
    samples. Here a sample is a cell, so a 1xN array is a perfectly good
    one-row image and rejecting it would be arbitrary.

    Args:
        z: The grid to measure.
        mark: The mark being drawn, so the message names the encode
            method the caller actually reached for.

    Returns:
        (rows, cols).

    Raises:
        Error: `z` is empty, has an empty row, or is ragged.
    """
    var method = (
        "Plot.encode_imshow()" if mark
        == Mark.IMSHOW else "Plot.encode_pcolormesh()"
    )
    var rows = len(z)
    if rows == 0:
        raise Error(
            method
            + ": there is no data to draw ("
            + mark.name()
            + " was given a grid with no rows)"
        )
    var cols = len(z[0])
    if cols == 0:
        raise Error(
            method
            + ": there is no data to draw ("
            + mark.name()
            + " was given a grid whose rows are empty)"
        )
    for r in range(1, rows):
        if len(z[r]) != cols:
            raise Error(
                method
                + ": z must be rectangular -- row 0 has "
                + String(cols)
                + " columns but row "
                + String(r)
                + " has "
                + String(len(z[r]))
            )
    return (rows, cols)


def _grid_min_max(z: List[List[Float64]]) raises -> Tuple[Float64, Float64]:
    """`z`'s smallest and largest values, the domain its colors span.

    A flat local loop rather than flattening into one `List[Float64]`
    and calling `_min_max`: the flattening would allocate a copy of the
    whole array, which for the array sizes this mark exists to handle is
    the single largest allocation in the render.

    Non-finite values are rejected for the reason `_min_max`'s own
    docstring gives at length -- a `NaN` poisons the domain into
    `(NaN, NaN)` because every comparison against it is false, and an
    `inf` survives the comparisons and produces a domain no color scale
    can project onto. The message names the cell, since an array big
    enough to want `imshow` is not one a reader can scan by eye.

    Args:
        z: The grid, already checked rectangular and non-empty.

    Returns:
        (min, max).

    Raises:
        Error: Any value is `NaN` or infinite.
    """
    var lo = z[0][0]
    var hi = z[0][0]
    for r in range(len(z)):
        for c in range(len(z[r])):
            var v = z[r][c]
            if not isfinite(v):
                raise Error(
                    "Plot.encode_imshow(): every value must be finite -- got "
                    + String(v)
                    + " at z["
                    + String(r)
                    + "]["
                    + String(c)
                    + "]"
                )
            if v < lo:
                lo = v
            if v > hi:
                hi = v
    return (lo, hi)


def _check_strictly_increasing(
    edges: List[Float64], count: Int, axis: String
) raises:
    """`Mark.PCOLORMESH`'s cell boundaries have to be `count + 1` values
    in strictly increasing order.

    Strictly, because two equal boundaries are a cell of zero width: it
    draws nothing, and its neighbors then sit next to each other with a
    value between them that never appears on the chart. Silently
    dropping a column of data is exactly the failure this package's
    encode checks exist to prevent.

    Increasing rather than merely monotonic: matplotlib accepts a
    descending coordinate array and flips the axis for it, but an axis
    that counts *down* because of the order values happened to arrive in
    is a surprising thing to infer from data. `Mark.IMSHOW` counts down
    deliberately and says so; here the caller can reverse the array and
    the values with it.

    Args:
        edges: The boundaries to check.
        count: How many cells they must bound, so `len(edges)` must be
            `count + 1`.
        axis: "x" or "y", for the message.

    Raises:
        Error: Wrong length, or not strictly increasing.
    """
    if len(edges) != count + 1:
        raise Error(
            "Plot.encode_pcolormesh(): "
            + axis
            + "_edges must have one more entry than z has "
            + ("columns" if axis == "x" else "rows")
            + " -- they bound the cells rather than sit at their centers (got "
            + String(len(edges))
            + " edges for "
            + String(count)
            + " cells, wanted "
            + String(count + 1)
            + ")"
        )
    for i in range(1, len(edges)):
        if not (edges[i] > edges[i - 1]):
            raise Error(
                "Plot.encode_pcolormesh(): "
                + axis
                + "_edges must be strictly increasing -- got "
                + String(edges[i - 1])
                + " then "
                + String(edges[i])
                + " at index "
                + String(i)
            )


def _edge_pixels(scale: LinearScale, values: List[Float64]) -> List[Float64]:
    """Every cell boundary's snapped pixel position, computed once.

    This one array is the whole seam argument (see the module
    docstring). `_fill_cells` reads `edges[i]` and `edges[i + 1]` for
    cell `i`, so the boundary between two cells is one number used
    twice, and no arithmetic can make the two sides disagree.

    A scale position is a pixel *index* -- `to_pixel(domain_min)` is
    `plot_x0`, the first column the plot rect covers -- and a column's
    geometry starts half a pixel before its index, so the `- 0.5` is
    what turns an index into the edge `fill_rect` wants. Without it the
    whole grid sits half a pixel right of and below the axes.

    Args:
        scale: The axis scale, with its pixel range already resolved
            by the frame.
        values: The boundaries in data units, in any order (the caller
            decides; `_fill_cells` takes min/max of each pair).

    Returns:
        One snapped pixel coordinate per value, in the same order.
    """
    var out = List[Float64](capacity=len(values))
    for i in range(len(values)):
        out.append(_snap_pixel_edge(scale.to_pixel(values[i]) - 0.5))
    return out^


def _same_color(a: Color, b: Color) -> Bool:
    """Whether two colors are identical in all four channels.

    Used only to merge horizontally adjacent cells into one rect, so it
    has to be exact: "close enough" would blur a real boundary between
    two values, which is the one thing an image must not do.
    """
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a


def _fill_cells[
    T: DrawTarget
](
    mut target: T,
    z: List[List[Float64]],
    x_edges: List[Float64],
    y_edges: List[Float64],
    color_scale: ColorScale,
) -> Int:
    """Paint the grid: one `fill_rect` per run of same-colored cells,
    shared by both marks.

    `x_edges`/`y_edges` are snapped pixel boundaries from
    `_edge_pixels`, `len(z[0]) + 1` and `len(z) + 1` of them. Their
    order does not matter -- `min`/`max` of each pair gives the rect,
    which is what lets `Mark.IMSHOW`'s descending y-axis and
    `Mark.PCOLORMESH`'s ascending one share this code. Taking min/max
    keeps the shared-boundary property intact: both cells still read the
    same list element, whichever side of the pair it lands on.

    A cell whose two boundaries snapped together covers no pixels and is
    skipped rather than drawn as a zero-width rect. That is not a
    special case to be sorry about: it is how a grid finer than the plot
    rect resolves, the nearest-neighbor decimation an image gets when it
    is displayed smaller than its own resolution. The cells that survive
    still tile the rect exactly, because a skipped cell's two boundaries
    are the same number and its neighbors meet at it.

    Returns:
        How many rects were filled. `_render_image` discards it; it is
        the number the module docstring's cost measurements were taken
        from, and the only way to observe the skip-and-merge behavior
        without counting pixels.
    """
    var rows = len(z)
    var cols = len(z[0])
    var filled = 0
    for r in range(rows):
        var ya = y_edges[r]
        var yb = y_edges[r + 1]
        var top = min(ya, yb)
        var bottom = max(ya, yb)
        if bottom <= top:
            continue

        # One open run at a time: its left edge, its right edge so far,
        # and the color every cell in it resolved to.
        var run_open = False
        var run_left = 0.0
        var run_right = 0.0
        var run_color = Color(0, 0, 0)
        for c in range(cols):
            var xa = x_edges[c]
            var xb = x_edges[c + 1]
            var left = min(xa, xb)
            var right = max(xa, xb)
            if right <= left:
                continue
            var color = color_scale.color_at(z[r][c])
            if run_open and _same_color(color, run_color) and left == run_right:
                run_right = right
                continue
            if run_open:
                target.fill_rect(
                    run_left, top, run_right - run_left, bottom - top, run_color
                )
                filled += 1
            run_open = True
            run_left = left
            run_right = right
            run_color = color
        if run_open:
            target.fill_rect(
                run_left, top, run_right - run_left, bottom - top, run_color
            )
            filled += 1
    return filled


def _render_image[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render `Mark.IMSHOW` or `Mark.PCOLORMESH`: the array as colored
    cells over a continuous frame, with a color legend beside it.

    The two marks differ in exactly two places, both decided here and
    both about *coordinates*, never about drawing:

    - Where the cell boundaries are. `IMSHOW` has none of its own, so it
      puts cell centers on the integers and boundaries on the
      half-integers: the grid spans `[-0.5, cols - 0.5]`, matching
      matplotlib's default `extent` and keeping the axis in the same
      grid-index units `Mark.CONTOUR` uses for the same `z`.
      `PCOLORMESH` is handed its boundaries.
    - Which way y counts. `IMSHOW` counts *down* -- row 0 at the top --
      because a raster's first row is its top scanline; see
      `_draw_continuous_axis_frame`'s `y_descending`. `PCOLORMESH`
      counts up like every other continuous mark, because its rows are
      positions on a real axis rather than scanlines. matplotlib splits
      them the same way and for the same reason.

    Colors come from `ColorScale.from_theme` over the array's own
    `[min, max]`, so `Theme(color_ramp=colormaps.viridis())` reaches
    this mark with no code here -- which matters more for an image than
    for anything else this package draws, since a three-stop ramp
    invents contrast in a scalar field where the data has none.

    No interpolation: each cell is one flat color. Nearest-neighbor is
    the default because it shows the array's
    actual resolution instead of implying detail that was interpolated
    into it.

    Aspect: the grid fills the plot rect, which is what every other mark
    here does and what makes the axes bound the data. It is *not*
    matplotlib's `imshow` default of square pixels -- see `imshow()`'s
    own docstring for what that costs and how to get square pixels back.
    """
    var mark = plot._mark
    var shape = _image_grid_shape(plot._image.z, mark)
    var rows = shape[0]
    var cols = shape[1]

    var x_values = List[Float64](capacity=cols + 1)
    var y_values = List[Float64](capacity=rows + 1)
    if mark == Mark.PCOLORMESH:
        if len(plot._image.x_edges) == 0 and len(plot._image.y_edges) == 0:
            raise Error(
                "Plot.mark_pcolormesh(): no cell edges to draw the mesh over"
                " -- "
                + mark.name()
                + " needs Plot.encode_pcolormesh(x_edges, y_edges, z), not"
                " Plot.encode_imshow(z), which has no coordinates of its own"
            )
        _check_strictly_increasing(plot._image.x_edges, cols, "x")
        _check_strictly_increasing(plot._image.y_edges, rows, "y")
        x_values = plot._image.x_edges.copy()
        y_values = plot._image.y_edges.copy()
    else:
        # The mirror of the check above, and the more dangerous
        # direction: a mark that quietly ignored coordinates the caller
        # supplied would draw a regular grid over irregular data and
        # look entirely plausible doing it. The other way round at least
        # has nothing to draw.
        if len(plot._image.x_edges) > 0 or len(plot._image.y_edges) > 0:
            raise Error(
                "Plot.mark_imshow(): "
                + mark.name()
                + " places cells by index and has no use for the cell edges"
                " Plot.encode_pcolormesh() supplied -- drawing them as a"
                " regular grid would misrepresent an irregular one. Use"
                " Plot.mark_pcolormesh() to honor the edges, or"
                " Plot.encode_imshow(z) to say the grid really is regular"
            )
        for c in range(cols + 1):
            x_values.append(Float64(c) - 0.5)
        for r in range(rows + 1):
            y_values.append(Float64(r) - 0.5)

    var extent = _grid_min_max(plot._image.z)
    var theme = plot._theme
    var sc = _Scaled(theme)
    var color_scale = ColorScale.from_theme(theme, extent[0], extent[1])

    # Measured against the render's shared font cache before the plot
    # rect is finalized, the way every other legend-bearing mark sizes
    # its column (see `_dynamic_legend_width`).
    var legend = _LegendLayout()
    if theme.show_legend:
        var legend_labels = List[String]()
        legend_labels.append(_format_fixed(color_scale.domain_max, 1))
        legend_labels.append(_format_fixed(color_scale.domain_min, 1))
        legend.right = _dynamic_legend_width(
            legend_labels,
            sc.continuous_legend_bar_width,
            sc,
            cache=cache,
        )
        legend.active = True

    var frame = _draw_continuous_axis_frame(
        target,
        LinearScale(x_values[0], x_values[cols], 0.0, 1.0),
        LinearScale(
            min(y_values[0], y_values[rows]),
            max(y_values[0], y_values[rows]),
            0.0,
            1.0,
        ),
        theme,
        legend,
        ox0,
        oy0,
        ox1,
        oy1,
        y_descending=mark == Mark.IMSHOW,
        cache=cache,
    )

    var x_px = _edge_pixels(frame.x_scale, x_values)
    var y_px = _edge_pixels(frame.y_scale, y_values)
    _ = _fill_cells(target, plot._image.z, x_px, y_px, color_scale)

    if theme.show_legend:
        _ = _draw_continuous_color_legend(
            target,
            frame.text_requests,
            color_scale,
            round_to_int(frame.x_scale.range_max) + sc.margin_right,
            frame.py0,
            theme,
        )

    return frame.result()


def imshow(
    z: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """Display a 2D array as an image: one colored cell per element, on
    continuous axes in row/column index units.

    `Mark.IMSHOW`, matplotlib's `imshow()`. This is the chart for
    anything that *is* an array rather than a table -- a matrix, a
    raster, a spectrogram, a correlation surface, a decoded PNG.
    `Mark.HEATMAP` looks like the same thing and is not: it takes
    categorical x and y labels with one value per pair, so a 512x512
    array would need 512 category labels.

    **Row 0 is at the top**, and the y-axis counts downward to match.
    That is matplotlib's `origin='upper'` default, the order a raster's
    scanlines arrive in, and the order a matrix is written in --
    `imshow(read_png(...))` comes out the right way up. It is the
    opposite of `contour()`, which puts row 0 at the bottom because its
    grid is a sampled surface rather than an image; matplotlib splits
    the two the same way.

    **The image fills the plot rect**, so its pixels are only square
    when the rect happens to be. matplotlib instead defaults `imshow` to
    square pixels and leaves the axes partly empty. Filling is the right
    default here because every other mark in this package fills its
    rect, and because the common case -- a matrix, a correlation
    surface, a field -- has no physical aspect to preserve. For a photo
    or anything else where a stretch would misrepresent the data, size
    the chart so the plot rect matches the array: the rect is `width`
    minus the left margin, the right margin and the legend column, and
    `height` minus the top and bottom margins, all of which `Theme`
    exposes.

    Cells are flat colors, no interpolation: what you see is the array's
    own resolution, not detail invented between samples.

    Color comes from the theme's scale over the array's own range.
    `Theme(color_ramp=colormaps.viridis())` is worth reaching for here
    more than anywhere else in this package -- a scalar field shown
    through a three-stop ramp gets contrast where the data has none,
    which is the specific problem perceptually uniform maps were built
    to fix.

    Args:
        z: The array, row-major (`z[row][col]`), rectangular and
            non-empty. Rows are the y axis and columns the x axis.
            Every value must be finite.
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
        from std.math import exp

        from dataviz import imshow
        from dataviz.colormaps import viridis
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            # Illustrative thermal-camera readings across a server rack.
            # Two hot components sit on top of a gentle exhaust gradient.
            var z = List[List[Float64]]()
            for r in range(48):
                var row = List[Float64]()
                for c in range(64):
                    var dx1 = (Float64(c) - 19.0) / 7.0
                    var dy1 = (Float64(r) - 17.0) / 6.0
                    var dx2 = (Float64(c) - 46.0) / 9.0
                    var dy2 = (Float64(r) - 31.0) / 8.0
                    var temperature = 24.0 + Float64(r) * 0.08
                    temperature += 31.0 * exp(-(dx1 * dx1 + dy1 * dy1))
                    temperature += 22.0 * exp(-(dx2 * dx2 + dy2 * dy2))
                    row.append(temperature)
                z.append(row^)

            var chart = imshow(
                z,
                theme=Theme(color_ramp=viridis()),
                title="Illustrative Server-Rack Thermal Scan (°C)",
                x_title="Sensor column",
                y_title="Sensor row",
            )
            save(chart, "docs/src/examples/out_imshow.svg")
        ```
    """
    var plot = Plot().mark_imshow().encode_imshow(z=z)
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def imshow[
    dtype: DType
](
    z: List[List[Scalar[dtype]]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`imshow()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (continuous.mojo). Each row is materialized in turn.
    Delegates to the concrete overload above.
    """
    var rows = List[List[Float64]](capacity=len(z))
    for r in range(len(z)):
        rows.append(_materialize_scalar_list(z[r]))
    return imshow(
        rows,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )


def pcolormesh(
    x_edges: List[Float64],
    y_edges: List[Float64],
    z: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """Display a 2D array over cell boundaries you supply: `imshow()`
    for a grid whose rows and columns are not evenly spaced.

    `Mark.PCOLORMESH`, matplotlib's `pcolormesh()` with 1D coordinate
    arrays. The array is the same as `imshow()`'s; what changes is that
    each cell's extent comes from `x_edges`/`y_edges` rather than from
    its index, so a log-spaced frequency axis, unequal time bins, or a
    grid that was never regular in the first place lands where it
    belongs instead of being stretched into evenly spaced columns.

    The edges *bound* the cells, so there is one more of each than the
    array has columns and rows -- `len(x_edges) == cols + 1`,
    `len(y_edges) == rows + 1`, the same rule matplotlib uses. Both must
    be strictly increasing.

    **Row 0 is at the bottom**, unlike `imshow()`. `y_edges[0]` is a
    position on a real axis, not a scanline, so the axis counts upward
    the way every other continuous mark's does. matplotlib makes the
    same split between its two functions.

    Cells are flat colors and the color scale is the theme's, exactly as
    in `imshow()` -- see that docstring for why `Theme(color_ramp=...)`
    matters here.

    Only 1D edges are supported: a fully curvilinear mesh (matplotlib's
    2D `X`/`Y`) would need a quad per cell rather than a rect, which is
    a different drawing path.

    Args:
        x_edges: Column boundaries, `cols + 1` of them, strictly
            increasing.
        y_edges: Row boundaries, `rows + 1` of them, strictly
            increasing.
        z: The array, row-major (`z[row][col]`), rectangular and
            non-empty. Every value must be finite.
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
        from std.math import exp, sin

        from dataviz import pcolormesh
        from dataviz.colormaps import magma
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            # Weather balloons are farther apart downrange and report at
            # uneven altitude bands, so each cell keeps its measured extent.
            var x_edges: List[Float64] = [
                0, 3, 7, 12, 18, 25, 33, 42, 52, 63, 75, 88, 102,
            ]
            var y_edges: List[Float64] = [
                0.0, 0.4, 0.9, 1.5, 2.3, 3.3, 4.6, 6.2, 8.0,
            ]

            var z = List[List[Float64]]()
            for r in range(len(y_edges) - 1):
                var row = List[Float64]()
                var altitude = (y_edges[r] + y_edges[r + 1]) / 2.0
                for c in range(len(x_edges) - 1):
                    var distance = (x_edges[c] + x_edges[c + 1]) / 2.0
                    var plume_x = (distance - 55.0) / 18.0
                    var plume_y = (altitude - 2.2) / 0.9
                    var temperature = 19.0 - 6.2 * altitude
                    temperature += 2.0 * sin(distance / 17.0)
                    temperature += 8.0 * exp(
                        -(plume_x * plume_x + plume_y * plume_y)
                    )
                    row.append(temperature)
                z.append(row^)

            var chart = pcolormesh(
                x_edges,
                y_edges,
                z,
                theme=Theme(color_ramp=magma()),
                title="Illustrative Atmospheric Temperature Cross-Section (°C)",
                x_title="Distance downrange (km)",
                y_title="Altitude (km)",
            )
            save(chart, "docs/src/examples/out_pcolormesh.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(x_edges=x_edges, y_edges=y_edges, z=z)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
