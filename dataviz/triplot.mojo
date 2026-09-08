"""Render a Delaunay triangulation as a mesh or colored triangles.

- **`Mark.TRIPLOT`** strokes each mesh edge and optionally marks samples.
- **`Mark.TRIPCOLOR`** fills each triangle from the values at its
  vertices, through `Theme`'s color scale. The unstructured counterpart
  of a heatmap: one patch per triangle instead of one per grid cell.

Both use data supplied by `encode_triplot()`; `TRIPLOT` needs only x and y.
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
from dataviz.scale import LinearScale
from dataviz.text import _Scaled
from dataviz.theme import Theme


struct _TriplotData(Copyable, Movable):
    """Data shared by `Mark.TRIPLOT` and `Mark.TRIPCOLOR`.

    `z` is empty for `TRIPLOT` and required for `TRIPCOLOR`.
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
"""Vertex-dot radius as a fraction of `Theme.point_radius`."""


comptime _SEAM_STROKE_WIDTH = 1.5
"""Triangle-outline width in `Theme.scale` units, used to hide seams."""


def _triplot_edges(t: _Triangulation) raises -> Tuple[List[Int], List[Int]]:
    """Every edge of the triangulation exactly once, as parallel lists of
    endpoint vertex indices.

    Shared interior edges are deduplicated with `_edge_key`.

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
    and the field at once.

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
    three put a given sample on the same pixel, and `render_layers()`
    takes all three: a mesh over a `tripcolor()` field, or a
    `scatter()` over a mesh, share one domain by construction.

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
    _validate_triplot(plot)

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

    _draw_triplot_layer(target, plot, frame.x_scale, frame.y_scale, frame.sc)
    return frame.result()


def _validate_triplot(plot: Plot) raises:
    """`Mark.TRIPLOT`'s pre-draw checks: matching x/y columns and at least
    one sample. `Mark.TRIPCOLOR` needs a `z` as well and has its own
    (`_validate_tripcolor`).

    A free function because `_render_layers_generic` has to run it
    in its own first pass -- a layer's x/y columns go into the combined
    domain before any frame exists, so a mismatched `encode_triplot()`
    has to be caught there rather than inside the drawing.
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


def _draw_triplot_layer[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    x_scale: LinearScale,
    y_scale: LinearScale,
    sc: _Scaled,
) raises:
    """Draw one `Mark.TRIPLOT` plot's mesh (and its vertex dots) into an
    already-laid-out continuous axis frame, the counterpart to
    `_draw_line_layer` in continuous.mojo.

    Shared by standalone and layered rendering so both stroke the same mesh
    and use the same styling.

    `sc` is the *layer's* own `_Scaled`, not the frame's: identical for a
    standalone render, but in a stack the frame belongs to `plots[0]`
    while the stroke width and vertex radius follow this layer's
    `Theme.scale`.

    Args:
        target: Where to draw.
        plot: The chart, whose `_triplot` data this reads.
        x_scale: The frame's x-scale, already ranged onto the plot rect.
        y_scale: The y-scale this layer draws against.
        sc: This layer's scaled theme metrics.
    """
    var theme = plot._theme
    var tri = delaunay(plot._triplot.x, plot._triplot.y)
    var edges = _triplot_edges(tri)
    if len(edges[0]) > 0:
        var mesh = Path()
        for i in range(len(edges[0])):
            var a = edges[0][i]
            var b = edges[1][i]
            mesh.move_to(
                x_scale.to_pixel(tri.xs[a]), y_scale.to_pixel(tri.ys[a])
            )
            mesh.line_to(
                x_scale.to_pixel(tri.xs[b]), y_scale.to_pixel(tri.ys[b])
            )
        target.stroke_path_aa(mesh, theme.mark_color, width=sc.scale)

    if plot._triplot.show_points:
        var radius = sc.point_radius * _POINT_RADIUS_FRACTION
        for i in range(len(plot._triplot.x)):
            target.fill_circle_aa(
                x_scale.to_pixel(plot._triplot.x[i]),
                y_scale.to_pixel(plot._triplot.y[i]),
                radius,
                theme.mark_color,
            )


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
    (`Theme(color_ramp=viridis())`) reaches this mark the same way
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
    class caused by independently antialiasing adjacent fills.
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
    _validate_tripcolor(plot)

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

    _draw_tripcolor_layer(target, plot, frame.x_scale, frame.y_scale, frame.sc)
    return frame.result()


def _validate_tripcolor(plot: Plot) raises:
    """`Mark.TRIPCOLOR`'s pre-draw checks: `_validate_triplot`'s, plus a
    `z` value at every sample.

    A free function for the same reason as `_validate_triplot` -- see
    that docstring.
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


def _draw_tripcolor_layer[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    x_scale: LinearScale,
    y_scale: LinearScale,
    sc: _Scaled,
) raises:
    """Draw one `Mark.TRIPCOLOR` plot's filled faces into an
    already-laid-out continuous axis frame, `_draw_triplot_layer`'s
    counterpart and the field a `render_layers()` stack puts a scatter or
    a mesh on top of.

    `sc` is the *layer's* own `_Scaled`, not the frame's: identical for a
    standalone render, but in a stack the frame belongs to `plots[0]`
    while `_SEAM_STROKE_WIDTH` scales by this layer's `Theme.scale`, and
    a seam sized from the wrong theme is the pale-webbing bug this mark's
    own docstring measures.

    Args:
        target: Where to draw.
        plot: The chart, whose `_triplot` data this reads.
        x_scale: The frame's x-scale, already ranged onto the plot rect.
        y_scale: The y-scale this layer draws against.
        sc: This layer's scaled theme metrics.
    """
    var theme = plot._theme
    var tri = delaunay(plot._triplot.x, plot._triplot.y)
    if tri.count() == 0:
        return

    var means = _triangle_means(tri, plot._triplot.z)
    var lo = means[0]
    var hi = means[0]
    for v in means:
        if v < lo:
            lo = v
        if v > hi:
            hi = v
    var color_scale = ColorScale.from_theme(theme, lo, hi)

    var seam_width = sc.scale * _SEAM_STROKE_WIDTH
    for k in range(tri.count()):
        var i0 = tri.tri[3 * k]
        var i1 = tri.tri[3 * k + 1]
        var i2 = tri.tri[3 * k + 2]
        var face = Path()
        face.move_to(x_scale.to_pixel(tri.xs[i0]), y_scale.to_pixel(tri.ys[i0]))
        face.line_to(x_scale.to_pixel(tri.xs[i1]), y_scale.to_pixel(tri.ys[i1]))
        face.line_to(x_scale.to_pixel(tri.xs[i2]), y_scale.to_pixel(tri.ys[i2]))
        face.close()
        var color = color_scale.color_at(means[k])
        # A single triangle has no self-intersection, so the fill rule
        # cannot matter -- NONZERO for consistency with every other
        # polygon fill in the package.
        target.fill_path_aa(face, color, fill_rule=FillRule.NONZERO)
        target.stroke_path_aa(face, color, width=seam_width)


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
    `Theme`'s color scale, so `Theme(color_ramp=viridis())` makes
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
