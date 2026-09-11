"""`Mark.HEXBIN` and `hexbin()`: a 2D histogram over a hexagonal
lattice -- continuous `(x, y)` points counted into hexagonal cells and
drawn as colored hexagons. The lattice tiles the plane without the
axis-aligned artifacts a rectangular grid shows on diagonal structure,
which is the reason it exists alongside `hist2d()`."""

from std.math import floor, sqrt

from canvas.color import Color
from canvas.fill_rule import FillRule
from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import ColorScale, _color_scale_for
from dataviz.legend import (
    _continuous_legend_labels,
    _draw_continuous_color_legend,
    _dynamic_legend_width,
)
from dataviz.plot import (
    Plot,
    _LegendLayout,
    _RenderResult,
    _data_extent,
    _draw_continuous_axis_frame,
    _finished,
)
from dataviz.scale import LinearScale
from dataviz.text import _Scaled
from dataviz.theme import Theme


struct _HexbinData(Copyable, Movable):
    """The points `Mark.HEXBIN` bins and the lattice size, from
    `encode_hexbin()`. Stored on `Plot._hexbin`. Binning happens at
    render time through `_hexbin_bins`, so the lattice is always the
    one the data's own extent gives."""

    var x: List[Float64]
    var y: List[Float64]
    var gridsize: Int

    def __init__(out self):
        self.x = List[Float64]()
        self.y = List[Float64]()
        self.gridsize = 0


struct _HexBins(Movable):
    """The nonempty cells of a hexagonal lattice: one center and count
    per cell, plus the lattice spacing that sizes the hexagon drawn at
    each center. See `_hexbin_bins`."""

    var cx: List[Float64]
    var cy: List[Float64]
    var count: List[Int]
    var sx: Float64
    var sy: Float64

    def __init__(out self):
        self.cx = List[Float64]()
        self.cy = List[Float64]()
        self.count = List[Int]()
        self.sx = 0.0
        self.sy = 0.0


def _hexbin_bins(
    x: List[Float64], y: List[Float64], gridsize: Int
) raises -> _HexBins:
    """Count `(x, y)` points into a hexagonal lattice `gridsize` cells
    across, matplotlib's `hexbin` lattice exactly.

    The lattice is two offset rectangular lattices over the data's
    bounding box. `nx = gridsize` columns of spacing `sx` and
    `ny = floor(nx / sqrt(3))` rows of spacing `sy` make the first;
    the second is the first shifted by half a spacing in both
    directions. Together the centers are those of a hexagonal tiling,
    each hexagon `sx` wide and `2 sy / 3` tall (pointy-top), regular
    when the plot rect is square. A point goes to whichever of its two
    candidate centers is nearer, with distance measured in lattice
    units and the vertical term weighted by 3 so the nearer center is
    the one whose hexagon contains the point. A point exactly as near
    to both goes to the offset lattice; that is the rule pinned by a
    test, since it is where implementations quietly differ.

    Only nonempty cells are returned, in row-major order of the first
    lattice then the second, so the drawing has nothing to skip and an
    empty cell is simply not there -- it shows the background, as an
    empty `hist2d()` bin does.

    Args:
        x: The horizontal coordinates.
        y: The vertical coordinates, one per `x`.
        gridsize: Cells across the x range, at least 1.

    Returns:
        The nonempty cells and the lattice spacing.

    Raises:
        Error: `x` and `y` differ in length or are empty, `gridsize`
            is below 1, or a coordinate is not finite.
    """
    if len(x) != len(y):
        raise Error(
            "hexbin(): x and y must be the same length -- got "
            + String(len(x))
            + " x values and "
            + String(len(y))
            + " y values"
        )
    if len(x) == 0:
        raise Error("hexbin(): no points to bin")
    if gridsize < 1:
        raise Error(
            "hexbin(): gridsize must be at least 1 -- got " + String(gridsize)
        )
    var xmin = x[0]
    var xmax = x[0]
    var ymin = y[0]
    var ymax = y[0]
    for i in range(len(x)):
        if not (x[i] == x[i]) or not (y[i] == y[i]):
            raise Error(
                "hexbin(): point " + String(i) + " has a NaN coordinate"
            )
        xmin = min(xmin, x[i])
        xmax = max(xmax, x[i])
        ymin = min(ymin, y[i])
        ymax = max(ymax, y[i])
    # A zero-span axis still needs a lattice to land on; a unit span
    # centered on the data gives every point the same cell.
    if xmax == xmin:
        xmin -= 0.5
        xmax += 0.5
    if ymax == ymin:
        ymin -= 0.5
        ymax += 0.5

    var nx = gridsize
    var ny = max(Int(floor(Float64(nx) / sqrt(3.0))), 1)
    var sx = (xmax - xmin) / Float64(nx)
    var sy = (ymax - ymin) / Float64(ny)

    # Counts for lattice 1, (nx + 1) x (ny + 1) cells, then lattice 2,
    # nx x ny cells, flat and row-major.
    var n1 = (nx + 1) * (ny + 1)
    var n2 = nx * ny
    var counts = List[Int](capacity=n1 + n2)
    for _ in range(n1 + n2):
        counts.append(0)
    for i in range(len(x)):
        var ix = (x[i] - xmin) / sx
        var iy = (y[i] - ymin) / sy
        var ix1 = Int(floor(ix + 0.5))
        var iy1 = Int(floor(iy + 0.5))
        var ix2 = Int(floor(ix))
        var iy2 = Int(floor(iy))
        var d1 = (ix - Float64(ix1)) ** 2 + 3.0 * (iy - Float64(iy1)) ** 2
        var d2 = (ix - Float64(ix2) - 0.5) ** 2 + 3.0 * (
            iy - Float64(iy2) - 0.5
        ) ** 2
        if d1 < d2:
            counts[iy1 * (nx + 1) + ix1] += 1
        else:
            # The offset lattice has no cell past its last row or
            # column; a point on the far edge of the box is nearer a
            # lattice-1 center anyway, but clamp so a rounding stray
            # cannot index past the end.
            var cx2 = min(ix2, nx - 1)
            var cy2 = min(iy2, ny - 1)
            counts[n1 + cy2 * nx + cx2] += 1

    var out = _HexBins()
    out.sx = sx
    out.sy = sy
    for j in range(ny + 1):
        for i in range(nx + 1):
            var c = counts[j * (nx + 1) + i]
            if c > 0:
                out.cx.append(xmin + Float64(i) * sx)
                out.cy.append(ymin + Float64(j) * sy)
                out.count.append(c)
    for j in range(ny):
        for i in range(nx):
            var c = counts[n1 + j * nx + i]
            if c > 0:
                out.cx.append(xmin + (Float64(i) + 0.5) * sx)
                out.cy.append(ymin + (Float64(j) + 0.5) * sy)
                out.count.append(c)
    return out^


def _hexagon_path(
    cx: Float64,
    cy: Float64,
    sx: Float64,
    sy: Float64,
    x_scale: LinearScale,
    y_scale: LinearScale,
    mut path: Path,
) raises:
    """Append the pointy-top hexagon centered on data point `(cx, cy)`
    to `path`, in pixels: `sx` wide, `2 sy / 3` tall, the cell of the
    lattice `_hexbin_bins` builds."""
    var hx = sx / 2.0
    var qy = sy / 6.0
    var ty = sy / 3.0
    path.move_to(x_scale.to_pixel(cx + hx), y_scale.to_pixel(cy - qy))
    path.line_to(x_scale.to_pixel(cx + hx), y_scale.to_pixel(cy + qy))
    path.line_to(x_scale.to_pixel(cx), y_scale.to_pixel(cy + ty))
    path.line_to(x_scale.to_pixel(cx - hx), y_scale.to_pixel(cy + qy))
    path.line_to(x_scale.to_pixel(cx - hx), y_scale.to_pixel(cy - qy))
    path.line_to(x_scale.to_pixel(cx), y_scale.to_pixel(cy - ty))
    path.close()


def _draw_hexbin_layer[
    T: DrawTarget
](
    mut target: T,
    bins: _HexBins,
    color_scale: ColorScale,
    x_scale: LinearScale,
    y_scale: LinearScale,
    sc: _Scaled,
) raises:
    """Fill every nonempty hexagon, one path per distinct count.

    Cells with the same count share a color, so they go into one path
    filled once under the nonzero rule: a shared edge inside one fill
    has full coverage and no seam. Cells of different counts still meet
    along antialiased edges, so each path is then stroked in its own
    color at the theme's line width, matplotlib's `edgecolors="face"`:
    the stroke covers the hairline the two fills leave between them.
    """
    var n = len(bins.count)
    if n == 0:
        return
    # Cells in ascending count, so one path per run of equal counts.
    var order = List[Int](capacity=n)
    for i in range(n):
        order.append(i)
    for i in range(n):
        for j in range(i + 1, n):
            if bins.count[order[j]] < bins.count[order[i]]:
                var t = order[i]
                order[i] = order[j]
                order[j] = t
    var at = 0
    while at < n:
        var c = bins.count[order[at]]
        var path = Path()
        while at < n and bins.count[order[at]] == c:
            var k = order[at]
            _hexagon_path(
                bins.cx[k], bins.cy[k], bins.sx, bins.sy, x_scale, y_scale, path
            )
            at += 1
        var color = color_scale.color_at(Float64(c))
        target.fill_path_aa(path, color, fill_rule=FillRule.NONZERO)
        target.stroke_path_aa(path, color, width=sc.line_width)


def _render_hexbin[
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
    """Render `Mark.HEXBIN`: the points binned by `_hexbin_bins`, each
    nonempty cell a hexagon colored by its count through the theme's
    ramp from zero to the fullest cell, over a continuous frame with a
    color legend beside it reading in counts. Empty cells are not
    drawn, for the reason `hist2d()` gives: zero is "nothing here".

    The frame's domains are the extent of the drawn hexagons -- the
    outermost centers sit on the data's bounding box, so a hexagon
    reaches half a cell past it -- padded as every scatter's extent is.
    That keeps the boundary cells whole inside the plot rect instead of
    cut at the axis, as matplotlib's autoscale keeps them.

    Args:
        target: Where to draw.
        plot: The chart, whose `_hexbin` data this reads.
        ox0: Left edge of the outer bounds.
        oy0: Top edge.
        ox1: Right edge.
        oy1: Bottom edge.
        cache: The render's font cache.

    Returns:
        The frame the axes were drawn into.

    Raises:
        Error: As `_hexbin_bins`.
    """
    var bins = _hexbin_bins(
        plot._hexbin.x, plot._hexbin.y, plot._hexbin.gridsize
    )
    var theme = plot._theme
    var sc = _Scaled(theme)
    var top = 0
    for c in bins.count:
        top = max(top, c)
    var color_scale = _color_scale_for(
        theme, plot._color_domain, 0.0, Float64(top)
    )

    var legend = _LegendLayout()
    if theme.show_legend:
        var legend_labels = _continuous_legend_labels(color_scale, theme)
        legend.right = _dynamic_legend_width(
            legend_labels,
            sc.continuous_legend_bar_width,
            sc,
            cache=cache,
        )
        legend.active = True

    var reach = List[Float64]()
    var reach_y = List[Float64]()
    for i in range(len(bins.count)):
        reach.append(bins.cx[i] - bins.sx / 2.0)
        reach.append(bins.cx[i] + bins.sx / 2.0)
        reach_y.append(bins.cy[i] - bins.sy / 3.0)
        reach_y.append(bins.cy[i] + bins.sy / 3.0)
    var frame = _draw_continuous_axis_frame(
        target,
        _data_extent(reach),
        _data_extent(reach_y),
        theme,
        legend,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    _draw_hexbin_layer(
        target, bins, color_scale, frame.x_scale, frame.y_scale, sc
    )
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


def hexbin(
    x: List[Float64],
    y: List[Float64],
    gridsize: Int = 30,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A hexagonal-bin density plot, matplotlib's `hexbin()`: `(x, y)`
    points counted into a lattice of hexagons `gridsize` cells across,
    each hexagon colored by how many points fell in it.

    `hist2d()`'s sibling for the same question -- where does a point
    cloud too dense to read as a scatter concentrate? -- with a lattice
    that tiles the plane without the axis-aligned artifacts a
    rectangular grid shows on diagonal structure: a hexagon's six
    neighbors are all equally near, so a ridge running at 30 degrees
    reads as a ridge rather than a staircase.

    Empty cells are left as background, not painted the bottom of the
    ramp; counted cells run from the bottom of the theme's ramp at zero
    to its top at the fullest cell, with the color legend reading in
    counts. A perceptual colormap (`Theme(color_ramp=viridis())`)
    matters most on this chart, where the eye reads structure into an
    uneven lightness ramp.

    `gridsize` is the number of hexagons across the x range; the row
    count follows so the hexagons are regular when the plot rect is
    square, as matplotlib sizes them. matplotlib's default of 100 is
    tuned for figures with many more pixels than a 640x420 chart, so
    the default here is 30.

    Args:
        x: The horizontal coordinates.
        y: The vertical coordinates, one per `x`.
        gridsize: Hexagons across the x range, at least 1.
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
        Error: `x` and `y` differ in length or are empty, or `gridsize`
            is below 1.

    Example:
        ```mojo
        from dataviz import hexbin, save
        from dataviz import Theme
        from dataviz.colormaps import viridis

        def main() raises:
            # Twenty thousand readings along a diagonal ridge with a
            # second, tighter cluster -- the shape a rectangular grid
            # turns into a staircase. A small linear congruential
            # generator keeps the example self-contained.
            var seed = 4321
            var xs = List[Float64]()
            var ys = List[Float64]()
            for i in range(20000):
                var u = List[Float64]()
                for _ in range(6):
                    seed = (seed * 1103515245 + 12345) % 2147483648
                    u.append(Float64(seed % 10000) / 10000.0 - 0.5)
                var gx = u[0] + u[1] + u[2]
                var gy = u[3] + u[4] + u[5]
                if i % 4 == 0:
                    xs.append(8.0 + 0.5 * gx)
                    ys.append(2.0 + 0.5 * gy)
                else:
                    var along = 3.0 * gx
                    xs.append(5.0 + along + 0.4 * gy)
                    ys.append(5.0 + 0.8 * along - 0.4 * gy)
            var chart = hexbin(
                xs,
                ys,
                gridsize=30,
                theme=Theme(color_ramp=viridis()),
                title="Illustrative Readings on a Hexagonal Lattice",
                x_title="Reading A",
                y_title="Reading B",
            )
            save(chart, "docs/src/examples/out_hexbin.svg")
        ```
    """
    var plot = Plot().mark_hexbin().encode_hexbin(x, y, gridsize)
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def hexbin[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    gridsize: Int = 30,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`hexbin()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (continuous.mojo). Delegates to the concrete overload
    above.

    Parameters:
        dtype: The element type of `x` and `y`.

    Args:
        x: The horizontal coordinates.
        y: The vertical coordinates, one per `x`.
        gridsize: Hexagons across the x range, at least 1.
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
    return hexbin(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        gridsize,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
