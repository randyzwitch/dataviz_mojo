"""The orthographic camera every 3D mark projects through: an elevation,
an azimuth, and the map from a data-space point to a 2D position plus a
depth (#345).

No drawing here, and nothing about any particular chart. A camera is a
numerical question with a right answer -- a known point at a known angle
lands at a hand-computable position -- so it is testable in isolation,
which is why it is the first of #345's five steps and why it is a leaf
module with no package imports.

**Why this lives here and not in canvas.** It is pure geometry with
nothing chart-specific in it, which is usually the signal that a thing
belongs in the drawing library -- that is the test #579 applies, and it
is how `Path.arrow_head`, `Path.regular_polygon` and `Path.extend` got
there. Put to canvas directly, the answer was a sharper test: does the
code encode something only canvas knows? `BoundsTarget` does -- a
stroke's box needs canvas's outline maths, text's needs its font
metrics. This does not. It is a 3x3 rotation and dropping an axis, and
any competent implementer writes the same thirty lines, so canvas would
own an API forever for a type it never calls and has no special
knowledge of.

Where canvas's 3D interest really starts is where 3D meets
rasterisation: a `fill_mesh` taking per-face depths, or the polygon
splitting that would make the painter's limitation below fixable rather
than documented. If #345 produces either, the camera goes upstream with
it as the thing that feeds it.

**Orthographic, not perspective.** Parallel lines stay parallel and a
unit of data is the same size wherever it sits in the scene, which is
what makes a 3D axis readable at all: under perspective the far end of
an axis is shorter than the near end, so a tick spacing means two
different things in one picture.

**Depth is for ordering, not for measuring.** `project()` returns a
`z` alongside the 2D position, and the only use for it is sorting what
to draw first: canvas is a painter's-algorithm rasteriser with no
z-buffer, so a nearer surface hides a farther one purely by being drawn
second. That makes the ordering the whole of the correctness, and it
has a documented failure: two shapes that interpenetrate, or one long
thin shape crossing another, have no single right order and a
centroid-depth sort will pick a wrong one. Splitting the geometry or a
real z-buffer are the fixes, and canvas has neither. Saying so is
part of the contract; pretending otherwise is not.
"""

from std.math import cos, pi, sin


comptime _DEGREES_TO_RADIANS = pi / 180.0
"""Both angles are given to callers in degrees and used here in
radians."""


struct Projected(ImplicitlyCopyable, Movable):
    """One point after projection: where it lands on the page, and how
    far away it is.

    `x`/`y` are in the camera's own 2D space, centered on the origin and
    in the same units the data was -- a frame maps them onto pixels the
    way a `LinearScale` maps any other value, so this struct knows
    nothing about a plot rect.

    `y` already points *up*, the way data does, rather than down the way
    pixels do. The frame flips it exactly once, where every other mark's
    y is flipped, instead of this module and the frame each flipping and
    the two having to agree.
    """

    var x: Float64
    var y: Float64

    var depth: Float64
    """Distance along the view direction, larger being farther from the
    camera. Comparable only against another `depth` from the same
    camera; it is an ordering key, not a measurement."""

    def __init__(out self, x: Float64, y: Float64, depth: Float64):
        """Build a projected point.

        Args:
            x: Horizontal position in camera space.
            y: Vertical position in camera space, y up.
            depth: Sort key, larger being farther away.
        """
        self.x = x
        self.y = y
        self.depth = depth


struct Camera3D(ImplicitlyCopyable, Movable):
    """An orthographic view of a scene, given as an elevation and an
    azimuth in degrees.

    `elev` is the angle above the x-y plane and `azim` the rotation
    about the z axis. The defaults, `elev=30` and `azim=-60`, look down
    on the scene from one corner: enough elevation to separate the
    three axes, and an azimuth that leaves none of them pointing
    straight at the reader, where it would have no length to read.

    The two rotations compose in one order and only one: azimuth about
    z first, then elevation about the rotated x. Doing it the other way
    round gives a different and wrong picture -- the axes tilt out of
    plane -- and the difference is invisible at `elev=0`, which is
    exactly the case a careless test would check.
    """

    var elev: Float64
    var azim: Float64

    var _cos_elev: Float64
    var _sin_elev: Float64
    var _cos_azim: Float64
    var _sin_azim: Float64

    def __init__(out self, elev: Float64 = 30.0, azim: Float64 = -60.0):
        """Build a camera. The four trigonometric values are computed
        once here rather than per point: a `surface3d` projects every
        vertex of a grid through one camera, and `sin`/`cos` per vertex
        would be the whole cost of the projection.

        Args:
            elev: Degrees above the x-y plane.
            azim: Degrees of rotation about the z axis.
        """
        self.elev = elev
        self.azim = azim
        var e = elev * _DEGREES_TO_RADIANS
        var a = azim * _DEGREES_TO_RADIANS
        self._cos_elev = cos(e)
        self._sin_elev = sin(e)
        self._cos_azim = cos(a)
        self._sin_azim = sin(a)

    def project(self, x: Float64, y: Float64, z: Float64) -> Projected:
        """Project a data-space point to camera space.

        Azimuth turns the scene about the z axis:

            x' =  x cos(a) + y sin(a)
            y' = -x sin(a) + y cos(a)

        then elevation tips it about the rotated x axis, which leaves
        `x'` alone and mixes `y'` with `z`:

            horizontal = x'
            vertical   = -y' sin(e) + z cos(e)
            depth      = -(y' cos(e) + z sin(e))

        **The minus sign on depth is the whole of the convention.** The
        camera sits at large `y'` and large `z` -- above the scene and
        on the near side of it -- which is what `vertical` already says
        by putting large `y'` low on the page, where the near edge of
        an elevated view belongs. Distance from that camera therefore
        *decreases* as `y'` and `z` grow, so the raw combination is
        nearness and the negation is what makes larger mean farther.

        At `elev=0, azim=0` this degenerates to `(x, z)` with depth
        `-y` -- a plain side-on view -- which is the case a test can
        check against the 2D frame without trusting any of the
        trigonometry.

        Args:
            x: Data-space x.
            y: Data-space y.
            z: Data-space z.

        Returns:
            The 2D position and the depth sort key.
        """
        var rx = x * self._cos_azim + y * self._sin_azim
        var ry = -x * self._sin_azim + y * self._cos_azim
        return Projected(
            rx,
            -ry * self._sin_elev + z * self._cos_elev,
            -(ry * self._cos_elev + z * self._sin_elev),
        )
