"""The 3D frame: data ranges to a centred unit cube, the cube through a
`Camera3D`, and the projection fitted to a plot rect (#345).

The second of #345's five steps. It owns the part of a 3D chart that is
not the mark: where a data point lands on the page, and the box, ticks
and labels that make the projection readable. Every 3D mark projects
through this and then draws its own glyphs.

**The cube is centred on the origin**, each axis normalised to
`[-0.5, 0.5]`, before it is projected. Rotation is about the origin, so
centring first is what makes the camera turn the scene rather than
swing it around the page. It also means one axis spanning nanometres
and another spanning kilometres come out the same size, which is the
only sensible default -- a 3D box is a viewing volume, not a shared
unit.

**The fit preserves aspect.** The eight corners are projected, their
bounding box measured, and one scale applied to both directions. Using
the width and height ratios separately would stretch the cube to fill
the rect, which shears a projection: a sphere would come out an
ellipsoid and equal data steps along x and y would look unequal.

**y is flipped exactly once**, here, where every other mark's y is
flipped. `Camera3D` hands back camera-space y pointing up, like data;
this is the one place it becomes a pixel row that grows downward.
"""

from canvas.vector.draw_target import DrawTarget

from dataviz.core.camera3d import Camera3D, Projected
from dataviz.core.scale import LinearScale, MinMax


struct _Extent3D(ImplicitlyCopyable, Movable):
    """The data ranges of the three axes, before normalisation."""

    var x: MinMax
    var y: MinMax
    var z: MinMax

    def __init__(out self, x: MinMax, y: MinMax, z: MinMax):
        """Build the extent.

        Args:
            x: The x range.
            y: The y range.
            z: The z range.
        """
        self.x = x
        self.y = y
        self.z = z


def _unit(value: Float64, span: MinMax) -> Float64:
    """`value` mapped onto `[-0.5, 0.5]` within `span`.

    A zero-width span puts everything at the centre rather than
    dividing by zero: one distinct value on an axis has no spread to
    show, and the honest picture is a flat slice, not an error.

    Args:
        value: The data value.
        span: That axis's range.

    Returns:
        The normalised coordinate.
    """
    var width = span.max - span.min
    if width <= 0.0:
        return 0.0
    return (value - span.min) / width - 0.5


struct Frame3D(Movable):
    """A camera, the data extent it views, and the plot rect it draws
    into: everything needed to turn a data point into a pixel.

    Built by `_fit_frame3d`, which measures the projected cube and
    chooses the scale and offset. Marks call `to_pixel` per vertex and
    `depth` to sort what to draw first.
    """

    var camera: Camera3D
    var extent: _Extent3D
    var scale: Float64
    var cx: Float64
    var cy: Float64

    def __init__(
        out self,
        camera: Camera3D,
        extent: _Extent3D,
        scale: Float64,
        cx: Float64,
        cy: Float64,
    ):
        """Build a fitted frame.

        Args:
            camera: The view.
            extent: The data ranges.
            scale: Pixels per unit of camera space, the same in both
                directions.
            cx: Pixel x the camera-space origin lands on.
            cy: Pixel y it lands on.
        """
        self.camera = camera
        self.extent = extent
        self.scale = scale
        self.cx = cx
        self.cy = cy

    def project(self, x: Float64, y: Float64, z: Float64) -> Projected:
        """A data point in camera space, normalised and projected but
        not yet in pixels.

        Args:
            x: Data x.
            y: Data y.
            z: Data z.

        Returns:
            Camera-space position and depth.
        """
        return self.camera.project(
            _unit(x, self.extent.x),
            _unit(y, self.extent.y),
            _unit(z, self.extent.z),
        )

    def to_pixel(
        self, x: Float64, y: Float64, z: Float64
    ) -> Tuple[Float64, Float64]:
        """A data point's pixel position.

        The y flip lives here: camera space points up, pixel rows grow
        downward, and this is the one place the two meet.

        Args:
            x: Data x.
            y: Data y.
            z: Data z.

        Returns:
            `(pixel_x, pixel_y)`.
        """
        var p = self.project(x, y, z)
        return (self.cx + p.x * self.scale, self.cy - p.y * self.scale)

    def depth(self, x: Float64, y: Float64, z: Float64) -> Float64:
        """A data point's sort key, larger being farther from the
        camera.

        Args:
            x: Data x.
            y: Data y.
            z: Data z.

        Returns:
            The depth.
        """
        return self.project(x, y, z).depth


def _cube_corners() -> List[Tuple[Float64, Float64, Float64]]:
    """The eight corners of the normalised cube, in unit coordinates."""
    var out = List[Tuple[Float64, Float64, Float64]]()
    for i in range(8):
        var cx = -0.5 if (i & 1) == 0 else 0.5
        var cy = -0.5 if (i & 2) == 0 else 0.5
        var cz = -0.5 if (i & 4) == 0 else 0.5
        out.append((cx, cy, cz))
    return out^


def _fit_frame3d(
    camera: Camera3D,
    extent: _Extent3D,
    px0: Int,
    py0: Int,
    px1: Int,
    py1: Int,
) raises -> Frame3D:
    """Fit the projected cube inside the plot rect, centred, with one
    scale for both directions.

    The eight corners bound everything the chart can draw, because every
    data point normalises into the cube. So fitting the corners fits the
    chart, and no mark can escape the rect by being at an extreme.

    Args:
        camera: The view.
        extent: The data ranges.
        px0: Plot rect left.
        py0: Plot rect top.
        px1: Plot rect right.
        py1: Plot rect bottom.

    Returns:
        The fitted frame.

    Raises:
        Error: The plot rect has no area.
    """
    if px1 <= px0 or py1 <= py0:
        raise Error(
            "Frame3D: the plot rect has no area to draw a cube in (got "
            + String(px1 - px0)
            + " by "
            + String(py1 - py0)
            + ")"
        )
    var corners = _cube_corners()
    var first = camera.project(corners[0][0], corners[0][1], corners[0][2])
    var min_x = first.x
    var max_x = first.x
    var min_y = first.y
    var max_y = first.y
    for i in range(1, len(corners)):
        var p = camera.project(corners[i][0], corners[i][1], corners[i][2])
        if p.x < min_x:
            min_x = p.x
        if p.x > max_x:
            max_x = p.x
        if p.y < min_y:
            min_y = p.y
        if p.y > max_y:
            max_y = p.y

    var span_x = max_x - min_x
    var span_y = max_y - min_y
    var avail_w = Float64(px1 - px0)
    var avail_h = Float64(py1 - py0)
    # One scale, the smaller of the two fits, so the cube keeps its
    # proportions. Taking each direction's own ratio would fill the rect
    # and shear the projection.
    var scale = avail_w / span_x if span_x > 0.0 else avail_w
    if span_y > 0.0:
        var by_height = avail_h / span_y
        if by_height < scale:
            scale = by_height

    # Centre the projected box in the rect. The camera-space origin is
    # not generally the middle of that box -- an elevation tips the cube
    # so its silhouette sits off-centre -- so the offset is measured
    # from the box, not assumed to be the rect's middle.
    var mid_x = (min_x + max_x) / 2.0
    var mid_y = (min_y + max_y) / 2.0
    return Frame3D(
        camera,
        extent,
        scale,
        (Float64(px0) + avail_w / 2.0) - mid_x * scale,
        (Float64(py0) + avail_h / 2.0) + mid_y * scale,
    )
