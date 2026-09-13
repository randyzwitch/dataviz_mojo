"""Render dispatch for the grid-cell charts (#524).

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
from dataviz.grid.calendar_heatmap import _render_calendar_heatmap
from dataviz.grid.corrplot import _render_corrplot
from dataviz.grid.heatmap import _render_heatmap
from dataviz.grid.image import _render_image
from dataviz.grid.marimekko import _render_marimekko
from dataviz.grid.punchcard import _render_punchcard


def _render_grid_family[
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
    if plot._mark == Mark.HEATMAP:
        return Optional(
            _render_heatmap(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.CALENDAR_HEATMAP:
        return Optional(
            _render_calendar_heatmap(
                target, plot, ox0, oy0, ox1, oy1, cache=cache
            )
        )
    if plot._mark == Mark.CORRPLOT:
        return Optional(
            _render_corrplot(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.PUNCHCARD:
        return Optional(
            _render_punchcard(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if (
        plot._mark == Mark.IMSHOW
        or plot._mark == Mark.PCOLORMESH
        or plot._mark == Mark.HIST2D
    ):
        return Optional(
            _render_image(
                target,
                plot,
                ox0,
                oy0,
                ox1,
                oy1,
                cache=cache,
                vector_target=vector_target,
            )
        )
    if plot._mark == Mark.MARIMEKKO:
        return Optional(
            _render_marimekko(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    return None
