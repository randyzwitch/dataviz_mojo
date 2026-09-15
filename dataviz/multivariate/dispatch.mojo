"""Render dispatch for the multi-dimension charts (#524).

Each `Plot.mark_*()` setter registers this family's callback for Canvas,
SVG, and PDF. `_render_generic` invokes the selected callback rather than
probing every family. Add a mark's render branch here and register these
adapters in its setter; see `plot.mojo`'s mark-adding checklist.

The "not mine" answer is an empty `Optional`. `_RenderResult` is
`Movable` but not `Copyable`, and this function is generic over
`T: DrawTarget` because `_render_generic` is, so that combination was
checked in a spike before the design rather than assumed to work.
"""

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.mark import Mark
from dataviz.plot import Plot, _RenderResult
from dataviz.multivariate.barbs import _render_barbs
from dataviz.multivariate.contour import _render_contour, _render_contourf
from dataviz.multivariate.parallel import _render_parallel
from dataviz.multivariate.quiver import _render_quiver
from dataviz.multivariate.streamplot import _render_streamplot
from dataviz.multivariate.tricontour import (
    _render_tricontour,
    _render_tricontourf,
)
from dataviz.multivariate.triplot import _render_tripcolor, _render_triplot


def _render_multivariate_family[
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
    if plot._mark == Mark.BARBS:
        return Optional(
            _render_barbs(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.CONTOUR:
        return Optional(
            _render_contour(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.CONTOURF:
        return Optional(
            _render_contourf(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.QUIVER:
        return Optional(
            _render_quiver(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.STREAMPLOT:
        return Optional(
            _render_streamplot(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.TRICONTOUR:
        return Optional(
            _render_tricontour(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.TRICONTOURF:
        return Optional(
            _render_tricontourf(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.TRIPLOT:
        return Optional(
            _render_triplot(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.TRIPCOLOR:
        return Optional(
            _render_tripcolor(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.PARALLEL:
        return Optional(
            _render_parallel(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    return None


def _callback_multivariate[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    mut cache: FontCache,
    vector_target: Bool,
) raises -> Optional[_RenderResult]:
    """Positional adapter for the stored family callback (#607)."""
    return _render_multivariate_family(
        target,
        plot,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
        vector_target=vector_target,
    )
