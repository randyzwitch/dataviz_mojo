"""Render dispatch for the polar-coordinate charts (#524).

`plot.mojo` calls one entry point per family instead of importing every
mark's render function and branching over every `Mark`. Adding a mark
touches this file and its own module rather than the hub.

The "not mine" answer is an empty `Optional`. `_RenderResult` is
`Movable` but not `Copyable`, and this function is generic over
`T: DrawTarget` because `_render_generic` is, so that combination was
checked in a spike before the design rather than assumed to work.
"""

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.mark import Mark
from dataviz.plot import Plot, _RenderResult
from dataviz.radial.gauge import _render_gauge
from dataviz.radial.nightingale import _render_nightingale
from dataviz.radial.polar import _render_polar
from dataviz.radial.polar_bar import _render_polar_bar
from dataviz.radial.radar import _render_radar
from dataviz.radial.radialbar import _render_radialbar


def _render_radial_family[
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
    vector_target: Bool = False,
) raises -> Optional[_RenderResult]:
    """Render `plot` when its mark is one of this family's.

    Args:
        target: The draw target.
        plot: The chart.
        ox0: Left bound.
        oy0: Top bound.
        ox1: Right bound.
        oy1: Bottom bound.
        cache: Shared font cache.
        vector_target: True when `target` keeps what it is given as
            shapes rather than pixels. Only the image marks read it, but
            every family takes it so the hub calls them all alike.

    Returns:
        The render result, or an empty `Optional` when the mark belongs
        to another family.
    """
    if plot._mark == Mark.NIGHTINGALE:
        return Optional(
            _render_nightingale(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.POLAR_BAR:
        return Optional(
            _render_polar_bar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.RADIALBAR:
        return Optional(
            _render_radialbar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.POLAR:
        return Optional(
            _render_polar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.RADAR:
        return Optional(
            _render_radar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.GAUGE:
        return Optional(
            _render_gauge(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    return None
