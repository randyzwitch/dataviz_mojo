"""The arrowhead: one filled triangle at the tip of a directed line,
shared by `Plot.annotate_arrow()` (annotations.mojo) and `Mark.QUIVER`
(quiver.mojo) so the two draw the same head rather than each growing
its own."""

from canvas.path import Path


comptime _ARROW_HEAD_LENGTH = 11.0
"""Pixel length of an arrowhead before `Theme.scale`.

Sized from the theme, never from the arrow's own length: a head scaled
to the shaft would be comically large on a short arrow pointing at a
nearby point, and invisible on a long one crossing the chart. Every
other piece of chart furniture is theme-sized for the same reason."""

comptime _ARROW_HEAD_HALF_WIDTH = 4.0
"""Half the arrowhead's base width, before `Theme.scale`. Narrower than
it is long, which is what reads as a direction rather than a wedge."""


def _arrow_head_path(
    tip_x: Float64,
    tip_y: Float64,
    ux: Float64,
    uy: Float64,
    head_len: Float64,
    head_half: Float64,
) raises -> Path:
    """The closed triangle whose tip is at `(tip_x, tip_y)` and whose
    base, `head_len` back along the unit direction `(ux, uy)`, is
    `2 * head_half` wide.

    One path, filled once, rather than three strokes: an antialiased
    edge is half-covered, so a head assembled from separate pieces
    shows pale seams where they meet.

    Args:
        tip_x: The tip, in pixels.
        tip_y: The tip.
        ux: Unit direction the arrow points in, x component.
        uy: Unit direction, y component (pixel y, growing downward).
        head_len: Tip-to-base length in pixels.
        head_half: Half the base width in pixels.

    Returns:
        The triangle, closed.
    """
    var base_x = tip_x - ux * head_len
    var base_y = tip_y - uy * head_len
    # Perpendicular, for the base corners.
    var nx = -uy
    var ny = ux
    var head = Path()
    head.move_to(tip_x, tip_y)
    head.line_to(base_x + nx * head_half, base_y + ny * head_half)
    head.line_to(base_x - nx * head_half, base_y - ny * head_half)
    head.close()
    return head^
