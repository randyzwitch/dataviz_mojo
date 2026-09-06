from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import ColorScale
from dataviz.contour import _Segments, _chain_segments, _crossing
from dataviz.delaunay import _Triangulation, _edge_key, delaunay
from dataviz.plot import (
    Plot,
    _LegendLayout,
    _RenderResult,
    _data_extent,
    _draw_continuous_axis_frame,
    _finished,
    _require_non_empty,
)
from dataviz.theme import Theme


struct _TriContourData(Copyable, Movable):
    """Scattered `(x, y, z)` samples and the level list, for
    `Mark.TRICONTOUR`. See `encode_tricontour()`. Stored on
    `Plot._tricontour`.

    Unlike `Mark.CONTOUR`'s grid, the points are in no particular order
    and need not be on any lattice; the triangulation supplies the
    connectivity at render time.
    """

    var x: List[Float64]
    var y: List[Float64]
    var z: List[Float64]
    var levels: List[Float64]
    var level_count: Int

    def __init__(out self):
        self.x = List[Float64]()
        self.y = List[Float64]()
        self.z = List[Float64]()
        self.levels = List[Float64]()
        self.level_count = 8


def _auto_levels_from(values: List[Float64], count: Int) -> List[Float64]:
    """`count` levels evenly spaced strictly inside `values`' range, the
    scattered-data counterpart to `contour.mojo`'s `_auto_levels`.

    Args:
        values: The z column.
        count: How many levels to place.

    Returns:
        The levels, ascending; empty when every value is equal.
    """
    var levels = List[Float64]()
    if len(values) == 0:
        return levels^
    var lo = values[0]
    var hi = values[0]
    for v in values:
        if v < lo:
            lo = v
        if v > hi:
            hi = v
    if hi <= lo:
        return levels^
    for i in range(count):
        levels.append(lo + (hi - lo) * Float64(i + 1) / Float64(count + 1))
    return levels^


def _tricontour_segments(
    t: _Triangulation, z: List[Float64], level: Float64
) -> _Segments:
    """Every isoline segment at `level`, one per triangle that the level
    crosses.

    A triangle is far simpler than a grid cell: with three corners there
    are only two cases. Either all three sit on the same side of the
    level and nothing crosses, or exactly one is alone on its side and
    the isoline cuts the two edges meeting at it -- a single segment,
    with no 16-case table and no saddle to resolve. That is the whole
    reason contouring scattered data goes through a triangulation.

    Segment ends carry the same kind of integer edge id the grid version
    uses (`_edge_key` over the two vertex indices), so `_chain_segments`
    joins them with no coordinate comparison and no tolerance.

    Args:
        t: The triangulation.
        z: One value per vertex, indexed as `t.xs`/`t.ys` are.
        level: The value to trace.

    Returns:
        Every segment found, unordered.
    """
    var segs = _Segments()
    for k in range(t.count()):
        var i0 = t.tri[3 * k]
        var i1 = t.tri[3 * k + 1]
        var i2 = t.tri[3 * k + 2]
        var a = z[i0]
        var b = z[i1]
        var c = z[i2]

        var above = 0
        if a > level:
            above += 1
        if b > level:
            above += 1
        if c > level:
            above += 1
        if above == 0 or above == 3:
            continue

        # The lone vertex is the one whose side differs from the other
        # two; the isoline crosses the two edges meeting there.
        var lone = i0
        var other1 = i1
        var other2 = i2
        if (b > level) != (a > level) and (b > level) != (c > level):
            lone = i1
            other1 = i2
            other2 = i0
        elif (c > level) != (a > level) and (c > level) != (b > level):
            lone = i2
            other1 = i0
            other2 = i1

        var zl = z[lone]
        var f1 = _crossing(zl, z[other1], level)
        var f2 = _crossing(zl, z[other2], level)
        var x1 = t.xs[lone] + (t.xs[other1] - t.xs[lone]) * f1
        var y1 = t.ys[lone] + (t.ys[other1] - t.ys[lone]) * f1
        var x2 = t.xs[lone] + (t.xs[other2] - t.xs[lone]) * f2
        var y2 = t.ys[lone] + (t.ys[other2] - t.ys[lone]) * f2

        segs.add(
            _edge_key(lone, other1),
            x1,
            y1,
            _edge_key(lone, other2),
            x2,
            y2,
        )
    return segs^


def _render_tricontour[
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
    """Render a `Mark.TRICONTOUR` plot: isolines over scattered `(x, y, z)`
    samples, the shape matplotlib's `tricontour()` draws.

    The points are Delaunay-triangulated (`delaunay`, Bowyer-Watson) and
    each level is traced over the triangles, chained into whole isolines
    by `contour.mojo`'s `_chain_segments`, and stroked one `Path` per
    line in that level's colour. Everything after the triangulation is
    the grid contour's machinery: only the connectivity differs.

    Axes are the data's own padded x/y extent, unlike `Mark.CONTOUR`'s
    grid-index units -- scattered samples carry real coordinates, so the
    frame is the same one a scatter of the same points would draw.

    Fewer than three distinct, non-collinear points triangulate to
    nothing and draw an empty frame rather than raising: the axes still
    report what the data spanned.
    """
    var n = len(plot._tricontour.x)
    if len(plot._tricontour.y) != n or len(plot._tricontour.z) != n:
        raise Error(
            "Plot.encode_tricontour(): x, y and z must have the same length"
            " (got "
            + String(n)
            + ", "
            + String(len(plot._tricontour.y))
            + " and "
            + String(len(plot._tricontour.z))
            + ")"
        )
    _require_non_empty(n, "Plot.encode_tricontour()")
    if plot._tricontour.level_count <= 0:
        raise Error(
            "Plot.mark_tricontour(): levels must be positive (got "
            + String(plot._tricontour.level_count)
            + ")"
        )

    var theme = plot._theme
    var frame = _draw_continuous_axis_frame(
        target,
        _data_extent(plot._tricontour.x),
        _data_extent(plot._tricontour.y),
        theme,
        _LegendLayout(),
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    var levels = plot._tricontour.levels.copy() if len(
        plot._tricontour.levels
    ) > 0 else _auto_levels_from(
        plot._tricontour.z, plot._tricontour.level_count
    )
    if len(levels) == 0:
        return frame.result()

    var tri = delaunay(plot._tricontour.x, plot._tricontour.y)
    if tri.count() == 0:
        return frame.result()

    var lo = levels[0]
    var hi = levels[0]
    for v in levels:
        if v < lo:
            lo = v
        if v > hi:
            hi = v
    var color_scale = ColorScale.from_theme(theme, lo, hi)

    for li in range(len(levels)):
        var level = levels[li]
        var color = color_scale.color_at(level)
        var segs = _tricontour_segments(tri, plot._tricontour.z, level)
        var lines = _chain_segments(segs)
        for k in range(len(lines)):
            ref line = lines[k]
            if len(line.xs) < 2:
                continue
            var path = Path()
            path.move_to(
                frame.x_scale.to_pixel(line.xs[0]),
                frame.y_scale.to_pixel(line.ys[0]),
            )
            for i in range(1, len(line.xs)):
                path.line_to(
                    frame.x_scale.to_pixel(line.xs[i]),
                    frame.y_scale.to_pixel(line.ys[i]),
                )
            target.stroke_path_aa(path, color, width=frame.sc.line_width)

    return frame.result()


def tricontour(
    x: List[Float64],
    y: List[Float64],
    z: List[Float64],
    levels: List[Float64] = List[Float64](),
    level_count: Int = 8,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A contour plot of scattered samples: isolines over `(x, y, z)`
    points that sit on no grid, Delaunay-triangulated first -- the
    reading for a field measured at stations, boreholes or any other
    irregular set of positions.

    `Mark.TRICONTOUR`: matplotlib's `tricontour()`. See
    `Plot.encode_tricontour()` (plot.mojo) for the data shape, and
    `contour()` for the regular-grid form.

    Args:
        x: Each sample's x position.
        y: Each sample's y position, one per `x` entry.
        z: Each sample's value, one per `x` entry.
        levels: The values to trace. Left empty (the default),
            `level_count` levels are spaced evenly inside `z`'s own
            range.
        level_count: How many levels to choose when `levels` is empty;
            defaults to `8`. Ignored when `levels` is given.
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
        from std.math import cos, sin

        from dataviz import tricontour
        from dataviz.plot import save

        def main() raises:
            var x = List[Float64]()
            var y = List[Float64]()
            var z = List[Float64]()
            var seed = 12345
            for _ in range(240):
                seed = (seed * 1103515245 + 12345) % 2147483648
                var px = Float64(seed % 1000) / 100.0
                seed = (seed * 1103515245 + 12345) % 2147483648
                var py = Float64(seed % 1000) / 100.0
                x.append(px)
                y.append(py)
                z.append(sin(px) * cos(py))

            var c = tricontour(x, y, z, level_count=9, title="Scattered samples")
            save(c, "docs/src/examples/out_tricontour.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_tricontour(levels=level_count)
        .encode_tricontour(x=x, y=y, z=z, levels=levels)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def tricontour[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    z: List[Scalar[dtype]],
    levels: List[Float64] = List[Float64](),
    level_count: Int = 8,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`tricontour()` generalized over numeric element type; see
    `scatter()`'s `DType` overload (continuous.mojo). Delegates to the concrete
    overload above.
    """
    return tricontour(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        _materialize_scalar_list(z),
        levels=levels,
        level_count=level_count,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
