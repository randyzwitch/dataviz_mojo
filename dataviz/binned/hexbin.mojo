"""`Mark.HEXBIN` and `hexbin()`: a 2D histogram over a hexagonal
lattice -- continuous `(x, y)` points counted into hexagonal cells and
drawn as colored hexagons. The lattice tiles the plane without the
axis-aligned artifacts a rectangular grid shows on diagonal structure,
which is the reason it exists alongside `hist2d()`."""

from std.math import floor, pi, sqrt

from canvas.color import Color
from canvas.fill_rule import FillRule
from canvas.geometry import Transform2D
from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.color_scale import ColorScale, _color_scale_for
from dataviz.core.legend import (
    _continuous_color_legend_layout,
    _draw_continuous_color_legend_at,
)
from dataviz.plot import (
    Plot,
    _RenderResult,
    _data_extent,
    _draw_continuous_axis_frame,
    _finished,
)
from dataviz.core.scale import LinearScale
from dataviz.core.text import _Scaled
from dataviz.core.theme import Theme


struct _HexbinData(Copyable, Defaultable, Movable):
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
    across.

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


def _unit_hexagon() raises -> Path:
    """A pointy-top regular hexagon at unit radius about the origin, the
    shape every cell is a scaled copy of.

    Built once per layer and mapped per cell with `_cell_transform`,
    which is how `Path.regular_polygon`'s own docstring says to draw a
    shape that is regular in data space through two different axis
    scales: it is not regular in pixels, so it cannot be built at
    pixel size directly.

    `-pi / 2` puts the first vertex at twelve o'clock. Scaled by
    `(sx / sqrt(3), sy / 3)` its six vertices are exactly the ones this
    function used to write out by hand -- the same points in the same
    winding, starting one vertex earlier round the ring (#579).

    Returns:
        The unit hexagon, closed.

    Raises:
        Error: Whatever `Path.regular_polygon()` raises.
    """
    var unit = Path()
    unit.regular_polygon(0.0, 0.0, 1.0, 6, -pi / 2.0)
    return unit^


def _cell_transform(
    cx: Float64,
    cy: Float64,
    sx: Float64,
    sy: Float64,
    x_scale: LinearScale,
    y_scale: LinearScale,
) raises -> Transform2D:
    """The transform taking `_unit_hexagon()` to the cell centered on
    data point `(cx, cy)`, in pixels.

    A cell is `sx` wide and `2 sy / 3` tall in data units, which is a
    regular hexagon scaled by `(sx / sqrt(3), sy / 3)` -- regular in
    pixels only when `sx = sy / sqrt(3)`, which the lattice does not
    promise. Composing that with each axis's data-to-pixel slope gives
    one affine map per cell.

    **Both scales must be linear.** `to_pixel` is affine only then, and
    a `Transform2D` cannot express a logarithmic axis: the hexagons
    would be drawn at plausible but wrong positions rather than
    failing. `_render_hexbin` passes `_data_extent`, so they always are
    -- but that is a property of one call site rather than a promise
    the type makes, so it is checked here instead of assumed.

    Args:
        cx: Cell center x, in data units.
        cy: Cell center y.
        sx: Lattice column pitch, in data units.
        sy: Lattice row pitch.
        x_scale: Data-to-pixel for x.
        y_scale: For y.

    Returns:
        The cell's transform, for `Path.transformed`.

    Raises:
        Error: Either scale is logarithmic.
    """
    if x_scale.is_log or y_scale.is_log:
        raise Error(
            "Mark.HEXBIN: a hexagonal cell is mapped to pixels with one"
            " affine transform per cell, which a logarithmic axis is"
            " not -- the cells would be drawn in the wrong places"
            " rather than raising. Give hexbin() linear axes."
        )
    # The slope of each axis, read from its own endpoints rather than
    # from a difference of two to_pixel calls, so a degenerate domain
    # shows up here as a division rather than as silently zero.
    var x_span = x_scale.domain_max - x_scale.domain_min
    var y_span = y_scale.domain_max - y_scale.domain_min
    var x_slope = (x_scale.range_max - x_scale.range_min) / x_span
    var y_slope = (y_scale.range_max - y_scale.range_min) / y_span
    return Transform2D(
        x_slope * sx / sqrt(3.0),
        y_slope * sy / 3.0,
        x_scale.to_pixel(cx),
        y_scale.to_pixel(cy),
    )


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
    color at the theme's line width:
    the stroke covers the hairline the two fills leave between them.
    """
    var n = len(bins.count)
    if n == 0:
        return
    # Cells in ascending count, so one path per run of equal counts.
    #
    # A counting sort rather than a comparison sort, because the key is
    # already a small non-negative integer: a cell's count. This was a
    # selection sort, which is quadratic in the number of nonempty cells,
    # and that count grows with `gridsize` squared -- so the sort, not
    # the drawing, set the cost of a fine grid. Linear in cells plus the
    # largest count now. Timings in benchmarks/METHODOLOGY.md.
    var top = 0
    for c in bins.count:
        if c > top:
            top = c
    var tally = List[Int](capacity=top + 2)
    for _ in range(top + 2):
        tally.append(0)
    for c in bins.count:
        tally[c + 1] += 1
    for c in range(1, top + 2):
        tally[c] += tally[c - 1]
    var order = List[Int](capacity=n)
    for _ in range(n):
        order.append(0)
    for i in range(n):
        var c = bins.count[i]
        order[tally[c]] = i
        tally[c] += 1
    # One unit hexagon for the whole layer: every cell is a transformed
    # copy of it, so the shape is built once rather than per cell.
    var unit = _unit_hexagon()
    var at = 0
    while at < n:
        var c = bins.count[order[at]]
        var path = Path()
        while at < n and bins.count[order[at]] == c:
            var k = order[at]
            path.extend(
                unit.transformed(
                    _cell_transform(
                        bins.cx[k],
                        bins.cy[k],
                        bins.sx,
                        bins.sy,
                        x_scale,
                        y_scale,
                    )
                )
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
    cut at the axis.

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
        plot._data[_HexbinData].x,
        plot._data[_HexbinData].y,
        plot._data[_HexbinData].gridsize,
    )
    var theme = plot._theme
    var sc = _Scaled(theme)
    var top = 0
    for c in bins.count:
        top = max(top, c)
    var color_scale = _color_scale_for(
        theme, plot._color_domain, 0.0, Float64(top)
    )

    var legend = _continuous_color_legend_layout(
        color_scale, theme, sc, cache=cache
    )

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
    _draw_continuous_color_legend_at(
        target,
        frame.text_requests,
        color_scale,
        legend,
        frame.px0,
        frame.py0,
        frame.px1,
        frame.py1,
        theme,
        cache=cache,
    )
    return frame.result()


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
    """A hexagonal-bin density plot: `(x, y)`
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
    square. The default of 30 suits a 640x420 chart; a figure with many
    more pixels can take more.

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
        from dataviz.core.colormaps import viridis

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
    var x_f = _materialize_scalar_list(x)
    var y_f = _materialize_scalar_list(y)
    var plot = Plot().mark_hexbin().encode_hexbin(x_f, y_f, gridsize)
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
