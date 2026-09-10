"""Moving a coordinate onto the pixel grid, for the two cases that
want it.

Both helpers started in `plot.mojo`, which is still their main caller.
They moved here when `marker.mojo` came to need `_snap_pixel_edge` for
the one marker shape drawn as a rect: `plot.mojo` imports `marker.mojo`,
so keeping them in either module would have made the pair circular.

Which shapes snap, and why, is in the two docstrings below -- the short
version is that only an axis-aligned filled rect and a hairline have a
crisp position to snap to, and everything else keeps its exact
geometry.
"""

from canvas.geometry import round_to_int
from std.math import floor


def _snap_pixel_edge(value: Float64) -> Float64:
    """`value` moved to the nearest whole-pixel boundary.

    Under the pixel-center convention a pixel `k` spans `k - 0.5` to
    `k + 0.5`, so the boundaries are the half-integers and this rounds
    to the nearest of them.

    Filled rectangles snap; nothing else does. A bar edge landing
    mid-pixel is unreadable as position -- a pixel on a 200px bar is
    half a percent, well under what comparing two bars resolves -- but
    it is visible as a soft edge, and an axis-aligned rectangle is the
    one shape where the hard edge is worth more than the fraction.
    Gridlines, paths and text keep their exact geometry, which is what
    made them sharper rather than blurrier.

    Snapping here rather than leaving it to the primitive matters under
    supersampling: `fill_rect` maps the box and snaps in *device*
    space, which resolves the fraction into an antialiased edge instead
    of removing it. Snapping in logical space first puts the mapped
    edge on a device block boundary, so the downsampled edge is hard.
    Both place the edge identically; only the crispness differs.

    The tie -- a coordinate exactly on a pixel center, equidistant from
    the boundary on either side -- is where data lands all the time: a
    symmetric domain's midpoint, a category band's center, the plot's
    middle row. Any nearest-boundary rule ties there; what matters is
    that the *rule* decides the tie rather than the last bit of a
    `LinearScale` multiply-add. `intercept + slope * v` can land one ULP
    under an exact whole number, and without the tolerance below that
    one ULP moved the edge a whole pixel -- deterministically on one
    platform, and a place two platforms could disagree (#314). The
    tolerance absorbs a few ULPs of a pixel coordinate (which is well
    under 1e5, so an ULP is under 1e-10) and is far too small to touch
    a real fraction.
    """
    return floor(value + _TIE_TOLERANCE) + 0.5


comptime _TIE_TOLERANCE = 1e-9
"""How far under a whole number a coordinate may sit and still snap as
that whole number would. Pixel-scale float error is ~1e-11; a real
sub-pixel fraction is never this small."""


def _snap_pixel_center(value: Float64) -> Float64:
    """`value` moved to the nearest pixel center.

    The thin-line counterpart of `_snap_pixel_edge`. A 1px line is
    drawn about its centerline, so it covers exactly one row when that
    centerline sits on a pixel center -- a whole number -- and spreads
    across two half-covered rows when it does not. Rectangles snap to
    boundaries because a rect is bounded by its edges; a line snaps to
    a center because it is centered on its coordinate.

    Only the fixed cross-axis coordinate snaps. The two ends run along
    the value axis and keep their exact positions, so a whisker still
    stops where its statistic falls.
    """
    return Float64(round_to_int(value))
