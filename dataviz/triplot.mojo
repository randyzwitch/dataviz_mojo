"""`Mark.TRIPLOT` and `Mark.TRIPCOLOR`: drawing the Delaunay
triangulation itself, rather than contouring through it (#344).

`delaunay()` (delaunay.mojo) has been in the package since #261 and was
rewritten to near-linear time in #325, but the only things that could
see its output were `Mark.TRICONTOUR` and `Mark.TRICONTOURF`, which
consume the triangles and draw isolines. Neither shows the mesh. These
two marks do:

- **`Mark.TRIPLOT`** strokes the mesh -- every edge once -- and, by
  default, marks the sample points. It is the tool for *looking at* a
  triangulation, which is the first thing anyone debugging scattered
  interpolation wants, and the first thing anyone reviewing `delaunay()`
  itself wants.
- **`Mark.TRIPCOLOR`** fills each triangle from the values at its
  vertices, through `Theme`'s color scale. The unstructured counterpart
  of a heatmap: one patch per triangle instead of one per grid cell.

Both take `encode_triplot()`'s columns, which is `encode_tricontour()`'s
shape minus the level list -- and minus `z` entirely for `TRIPLOT`,
which needs only positions.
"""

from std.collections import Dict

from canvas.color import Color
from canvas.fill_rule import FillRule
from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import ColorScale
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


struct _TriplotData(Copyable, Movable):
    """Scattered `(x, y)` positions, an optional per-vertex `z`, and the
    one glyph knob `mark_triplot()` sets. See `encode_triplot()`. Stored
    on `Plot._triplot`, shared by `Mark.TRIPLOT` and `Mark.TRIPCOLOR` the
    way `_TriContourData` is shared by the two contour marks.

    `z` is empty for `Mark.TRIPLOT`, which draws connectivity and nothing
    else, and required for `Mark.TRIPCOLOR`, which colors by it.

    **Why there is no per-triangle value column.** matplotlib's
    `tripcolor` accepts `facecolors=` -- one value per triangle instead
    of one per vertex -- because its caller can hand it a `Triangulation`
    object and so knows what order the triangles are in. Here the
    triangulation is built inside the render, and its order is an
    artifact of Bowyer-Watson's insertion sequence (see delaunay.mojo's
    `_grid_order`), so a caller has nothing to index against. Offering
    the column would mean promising an order the algorithm does not
    promise. #397 tracks exposing the triangulation itself, which is what
    would make per-triangle values expressible.
    """

    var x: List[Float64]
    var y: List[Float64]
    var z: List[Float64]
    var show_points: Bool

    def __init__(out self):
        self.x = List[Float64]()
        self.y = List[Float64]()
        self.z = List[Float64]()
        self.show_points = True


comptime _POINT_RADIUS_FRACTION = 0.6
"""Vertex dots are this fraction of `Theme.point_radius`.

A triplot's dots mark where a sample is, they are not the chart's
subject the way a scatter's are -- the mesh is. At the full scatter
radius a few hundred samples draw as overlapping blobs with the edges
lost underneath them, which defeats the point of drawing the mesh at
all. Scaling the radius rather than hard-coding a size keeps
`Theme.point_radius` and `Theme.scale` in charge, so a HiDPI export and
a deliberately large-marker theme both still work.
"""


comptime _SEAM_STROKE_WIDTH = 1.5
"""How wide, in `Theme.scale` units, `Mark.TRIPCOLOR` strokes each
triangle's own outline in its own fill color.

This is the whole anti-seam mechanism -- see `_render_tripcolor` for why
`_fill_region_above`'s one-fill-per-color trick cannot be used here, and
for the white-page/black-page measurement that picked 1.5 over 1.0. It
is in `scale` units rather than pixels so a HiDPI export gets the same
half-pixel-of-overlap behavior at its own resolution.
"""


def _triplot_edges(t: _Triangulation) raises -> Tuple[List[Int], List[Int]]:
    """Every edge of the triangulation exactly once, as parallel lists of
    endpoint vertex indices.

    Each interior edge belongs to two triangles, so walking `t.tri` and
    emitting three edges per triangle yields most of them twice. Stroking
    a duplicate is not free and not invisible: an antialiased line drawn
    twice over itself composites to a darker, apparently heavier line
    than one drawn once, so an undeduplicated mesh shows its interior
    edges bolder than its hull edges -- exactly backwards. It also costs
    roughly twice the path.

    Deduplication goes through delaunay.mojo's own `_edge_key`, the
    canonical id for an undirected vertex pair that `_tricontour_segments`
    already uses to chain isolines. Two triangles that share an edge see
    it in opposite directions, and the key is order-independent, so they
    agree.

    Args:
        t: The triangulation to walk.

    Returns:
        The two endpoint index lists, one entry per distinct edge.
    """
    var ea = List[Int]()
    var eb = List[Int]()
    var seen = Dict[Int, Bool]()
    for k in range(t.count()):
        var v0 = t.tri[3 * k]
        var v1 = t.tri[3 * k + 1]
        var v2 = t.tri[3 * k + 2]
        for e in range(3):
            var a = v0
            var b = v1
            if e == 1:
                a = v1
                b = v2
            elif e == 2:
                a = v2
                b = v0
            var key = _edge_key(a, b)
            if key in seen:
                continue
            seen[key] = True
            ea.append(a)
            eb.append(b)
    return (ea^, eb^)


def _triangle_means(t: _Triangulation, z: List[Float64]) -> List[Float64]:
    """Each triangle's flat-shading value: the mean of the values at its
    three vertices.

    **Flat, not Gouraud.** A per-vertex value means each triangle spans a
    range of values, and there are two readings of that. matplotlib's
    `tripcolor` defaults to `shading='flat'`, which paints each triangle
    one color from the mean of its three vertices, and offers
    `shading='gouraud'` to interpolate across the face instead. This
    ships flat, the default, for the reason the interpolated form is an
    addition rather than a variant: `DrawTarget.fill_path_aa` fills a
    path with a single color, so Gouraud would need either per-pixel
    evaluation of the barycentric interpolant or subdividing every
    triangle until each piece is small enough to look continuous. Both
    are real work with real cost, and neither is what a caller reaching
    for `tripcolor` usually wants -- the flat form is what shows the mesh
    and the field at once. #398 tracks the interpolated form.

    Args:
        t: The triangulation.
        z: One value per vertex, indexed as `t.xs`/`t.ys` are.

    Returns:
        One value per triangle, in `t.tri` order.
    """
    var out = List[Float64](capacity=t.count())
    for k in range(t.count()):
        out.append(
            (z[t.tri[3 * k]] + z[t.tri[3 * k + 1]] + z[t.tri[3 * k + 2]]) / 3.0
        )
    return out^


def _render_triplot[
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
    """Render a `Mark.TRIPLOT` plot: the Delaunay mesh over scattered
    `(x, y)` samples, the shape matplotlib's `triplot()` draws.

    The points are triangulated (`delaunay`, Bowyer-Watson), the
    triangles' edges deduplicated by `_triplot_edges`, and all of them
    stroked as subpaths of **one** `Path` -- a mesh over 20,000 points
    has some 60,000 edges, and one stroke call for the lot costs far less
    than 60,000 of them.

    Axes are the samples' own padded extent -- the same frame
    `Mark.TRICONTOUR` and a `scatter()` of the same points draw, so all
    three put a given sample on the same pixel. (They still cannot be
    layered: `render_layers()` takes only `Mark.POINT`/`LINE`/`AREA`.
    #401.)

    Vertex dots are drawn on top when `mark_triplot(show_points=True)`,
    which is this package's default and a deliberate divergence:
    matplotlib's `triplot()` draws lines only unless the caller asks for
    markers in its format string. A mesh with no vertices shown does not
    say which crossings are samples and which are just where edges
    happen to meet, and telling those apart is most of what the mark is
    for.

    Degenerate input -- fewer than three points, or collinear ones --
    triangulates to nothing. The frame and the sample dots are still
    drawn rather than raising, so the chart says "here are your points,
    they support no triangle" instead of going blank.

    Args:
        target: Where to draw.
        plot: The chart, whose `_triplot` data this reads.
        ox0: Left edge of the outer bounds.
        oy0: Top edge.
        ox1: Right edge.
        oy1: Bottom edge.
        cache: The render's font cache.

    Returns:
        The frame the axes were drawn into.

    Raises:
        Error: Empty data, or mismatched column lengths.
    """
    var n = len(plot._triplot.x)
    if len(plot._triplot.y) != n:
        raise Error(
            "Plot.encode_triplot(): x and y must have the same length (got "
            + String(n)
            + " and "
            + String(len(plot._triplot.y))
            + ")"
        )
    _require_non_empty(n, "Plot.encode_triplot()")

    var theme = plot._theme
    var frame = _draw_continuous_axis_frame(
        target,
        _data_extent(plot._triplot.x),
        _data_extent(plot._triplot.y),
        theme,
        _LegendLayout(),
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    var tri = delaunay(plot._triplot.x, plot._triplot.y)
    var edges = _triplot_edges(tri)
    if len(edges[0]) > 0:
        var mesh = Path()
        for i in range(len(edges[0])):
            var a = edges[0][i]
            var b = edges[1][i]
            mesh.move_to(
                frame.x_scale.to_pixel(tri.xs[a]),
                frame.y_scale.to_pixel(tri.ys[a]),
            )
            mesh.line_to(
                frame.x_scale.to_pixel(tri.xs[b]),
                frame.y_scale.to_pixel(tri.ys[b]),
            )
        target.stroke_path_aa(mesh, theme.mark_color, width=frame.sc.scale)

    if plot._triplot.show_points:
        var radius = frame.sc.point_radius * _POINT_RADIUS_FRACTION
        for i in range(n):
            target.fill_circle_aa(
                frame.x_scale.to_pixel(plot._triplot.x[i]),
                frame.y_scale.to_pixel(plot._triplot.y[i]),
                radius,
                theme.mark_color,
            )

    return frame.result()


def _render_tripcolor[
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
    """Render a `Mark.TRIPCOLOR` plot: every triangle of the Delaunay
    mesh filled from the values at its vertices, the shape matplotlib's
    `tripcolor()` draws.

    Shading is flat -- one color per triangle, from the mean of its three
    vertex values; see `_triangle_means` for why that and not Gouraud.
    Colors come from `ColorScale.from_theme`, so a `Theme.color_ramp`
    (`Theme(color_ramp=viridis())`, #332) reaches this mark the same way
    it reaches every other continuous one.

    **The color domain is the triangle means, not the vertex values.**
    Averaging pulls every triangle's value inward from `z`'s own range,
    so normalizing against the vertex range would leave both ends of the
    ramp unused and the chart flatter than the data. matplotlib
    normalizes over the face values for the same reason. The cost is that
    `tripcolor` and `tricontourf` of the same samples do not share a
    color mapping, which is the honest consequence of flat shading:
    a triangle's color is a property of the triangle, not of a point.

    **No pale seams between the fills.** Two adjacent triangles filled
    independently each antialias the edge they share, and two
    half-covered pixels composited over the background do not add up to a
    covered one -- the mesh comes out webbed with pale lines, the bug
    class that has hit this repo in #315, #318, #327, #359 and #360.
    `_fill_region_above` (tricontour.mojo) avoids it by putting every
    triangle of one color into a single nonzero fill, so shared edges are
    interior and cancel. That is not available here: flat shading gives
    almost every triangle a *different* color, so there is nothing to
    group. Instead each triangle is stroked along its own outline in its
    own fill color, which is matplotlib's `edgecolors="face"`.

    A stroke of width `w` extends a triangle's coverage `w / 2` past its
    edge, so the two triangles' extended regions overlap in a band
    straddling the edge and there is nothing left for the page to show
    through. How wide `w` has to be for that to hold in practice is a
    measurement, not an argument, and the measurement is:
    **render the same mesh twice, once on a white page and once on a
    black one, and compare the interior pixels.** A pixel that changes is
    a pixel where the background is getting through; a pixel that does
    not cannot be showing any. Taken over the middle of a scattered mesh
    at `raster_supersample=1` with gridlines off, so that nothing but the
    page is underneath, the worst interior pixel moves **5 levels out of
    255 at `w = 1.0`** and **1 level at `w = 1.5`**, against a 255-level
    swing in what is beneath it -- hence `_SEAM_STROKE_WIDTH`. With no
    stroke at all it moves **87**, a third of the way to the page: that
    is the seam, and it is what the fix has to remove.
    `test_tripcolor_lets_no_background_through_between_triangles` keeps
    that measurement as a standing assertion.

    The price is that the later of two neighbors wins their shared
    boundary by up to `w / 2`. That is sub-pixel, invisible, and the same
    trade the pixel-snapped heatmap makes.

    Args:
        target: Where to draw.
        plot: The chart, whose `_triplot` data this reads.
        ox0: Left edge of the outer bounds.
        oy0: Top edge.
        ox1: Right edge.
        oy1: Bottom edge.
        cache: The render's font cache.

    Returns:
        The frame the axes were drawn into.

    Raises:
        Error: Empty data, or mismatched column lengths.
    """
    var n = len(plot._triplot.x)
    if len(plot._triplot.y) != n or len(plot._triplot.z) != n:
        raise Error(
            "Plot.encode_triplot(): x, y and z must have the same length (got "
            + String(n)
            + ", "
            + String(len(plot._triplot.y))
            + " and "
            + String(len(plot._triplot.z))
            + ") -- Mark.TRIPCOLOR needs a value at every sample"
        )
    _require_non_empty(n, "Plot.encode_triplot()")

    var theme = plot._theme
    var frame = _draw_continuous_axis_frame(
        target,
        _data_extent(plot._triplot.x),
        _data_extent(plot._triplot.y),
        theme,
        _LegendLayout(),
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    var tri = delaunay(plot._triplot.x, plot._triplot.y)
    if tri.count() == 0:
        return frame.result()

    var means = _triangle_means(tri, plot._triplot.z)
    var lo = means[0]
    var hi = means[0]
    for v in means:
        if v < lo:
            lo = v
        if v > hi:
            hi = v
    var color_scale = ColorScale.from_theme(theme, lo, hi)

    var seam_width = frame.sc.scale * _SEAM_STROKE_WIDTH
    for k in range(tri.count()):
        var i0 = tri.tri[3 * k]
        var i1 = tri.tri[3 * k + 1]
        var i2 = tri.tri[3 * k + 2]
        var face = Path()
        face.move_to(
            frame.x_scale.to_pixel(tri.xs[i0]),
            frame.y_scale.to_pixel(tri.ys[i0]),
        )
        face.line_to(
            frame.x_scale.to_pixel(tri.xs[i1]),
            frame.y_scale.to_pixel(tri.ys[i1]),
        )
        face.line_to(
            frame.x_scale.to_pixel(tri.xs[i2]),
            frame.y_scale.to_pixel(tri.ys[i2]),
        )
        face.close()
        var color = color_scale.color_at(means[k])
        # A single triangle has no self-intersection, so the fill rule
        # cannot matter -- NONZERO for consistency with every other
        # polygon fill in the package.
        target.fill_path_aa(face, color, fill_rule=FillRule.NONZERO)
        target.stroke_path_aa(face, color, width=seam_width)

    return frame.result()


def triplot(
    x: List[Float64],
    y: List[Float64],
    show_points: Bool = True,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """The Delaunay triangulation of scattered points, drawn as itself:
    every edge of the mesh stroked once, with a dot at each sample -- the
    mesh-inspection view, and what you look at when a `tricontour()` or
    `tripcolor()` over the same points comes out wrong.

    `Mark.TRIPLOT`: matplotlib's `triplot()`. See `_render_triplot` for
    the drawing, `tripcolor()` for the filled counterpart, and
    `tricontour()` for contouring the same samples.

    Interior edges are shared by two triangles and are stroked once, not
    twice: a doubled antialiased line reads heavier than a single one,
    which would make the mesh's interior look bolder than its hull.

    Args:
        x: Each sample's x position.
        y: Each sample's y position, one per `x` entry.
        show_points: Draw a dot at every sample on top of the mesh.
            Defaults to `True`, where matplotlib's `triplot()` draws
            lines only: without the dots a reader cannot tell a sample
            from a place where edges happen to meet, which is most of
            what the mark is for. Pass `False` for the mesh alone.
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
        Error: Empty data, or `x` and `y` of different lengths.

    Example:
        ```mojo
        from std.math import cos, sin

        from dataviz import triplot
        from dataviz.plot import save

        def main() raises:
            # Samples on a polar lattice: one per ring, each ring turned
            # a little against the one inside it so no two rings line up
            # radially. Delaunay adapts the cell size to the local
            # density, so the mesh coarsens outward on its own.
            var x: List[Float64] = [0.0]
            var y: List[Float64] = [0.0]
            for ring in range(1, 7):
                var r = Float64(ring)
                var spokes = 6 * ring
                var turn = 0.35 * Float64(ring)
                for s in range(spokes):
                    var a = 6.283185307179586 * Float64(s) / Float64(spokes)
                    x.append(r * cos(a + turn))
                    y.append(r * sin(a + turn))

            var c = triplot(x, y, title="Delaunay mesh of a polar lattice")
            save(c, "docs/src/examples/out_triplot.svg")
        ```
    """
    var plot = (
        Plot().mark_triplot(show_points=show_points).encode_triplot(x=x, y=y)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def tripcolor(
    x: List[Float64],
    y: List[Float64],
    z: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A pseudocolor plot over scattered samples: the points are Delaunay-
    triangulated and every triangle filled from the values at its three
    vertices -- the unstructured counterpart of a heatmap, for a field
    measured at stations, boreholes or any other irregular set of
    positions.

    `Mark.TRIPCOLOR`: matplotlib's `tripcolor()`. See `_render_tripcolor`
    for the painting, `triplot()` for the bare mesh, and `tricontourf()`
    for filled contour *bands* over the same samples.

    Shading is flat: one color per triangle, from the mean of its three
    vertex values, which is matplotlib's default. Colors come from
    `Theme`'s color scale, so `Theme(color_ramp=viridis())` (#332) makes
    it perceptually uniform.

    Prefer this over `tricontourf()` when you want to see the sampling
    itself -- every triangle is visible, so the chart shows where the
    data is dense and where it is guesswork. Prefer `tricontourf()` when
    the field matters more than the mesh.

    Args:
        x: Each sample's x position.
        y: Each sample's y position, one per `x` entry.
        z: The value at each sample, one per `x` entry.
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
        Error: Empty data, or columns of different lengths.

    Example:
        ```mojo
        from std.math import cos, sin

        from dataviz import tripcolor, viridis
        from dataviz.theme import Theme
        from dataviz.plot import save

        def main() raises:
            var x = List[Float64]()
            var y = List[Float64]()
            var z = List[Float64]()
            var seed = 12345
            for _ in range(400):
                seed = (seed * 1103515245 + 12345) % 2147483648
                var px = Float64(seed % 1000) / 100.0
                seed = (seed * 1103515245 + 12345) % 2147483648
                var py = Float64(seed % 1000) / 100.0
                x.append(px)
                y.append(py)
                z.append(sin(px) * cos(py))

            var c = tripcolor(
                x,
                y,
                z,
                theme=Theme(color_ramp=viridis()),
                title="Scattered samples, one color per triangle",
            )
            save(c, "docs/src/examples/out_tripcolor.svg")
        ```
    """
    var plot = Plot().mark_tripcolor().encode_triplot(x=x, y=y, z=z)
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def triplot[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    show_points: Bool = True,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`triplot()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (continuous.mojo). Delegates to the concrete overload
    above.
    """
    return triplot(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        show_points=show_points,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )


def tripcolor[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    z: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`tripcolor()` generalized over numeric element type; see
    `scatter()`'s `DType` overload (continuous.mojo). Delegates to the
    concrete overload above.
    """
    return tripcolor(
        _materialize_scalar_list(x),
        _materialize_scalar_list(y),
        _materialize_scalar_list(z),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
