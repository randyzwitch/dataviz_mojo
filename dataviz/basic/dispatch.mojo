"""Render dispatch for the core chart types (#524).

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
from dataviz.basic.arc import _render_arc
from dataviz.basic.bar import _render_bar, _render_horizontal_bar
from dataviz.basic.single_axis import _render_single_axis


def _render_basic_family[
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
    if plot._mark == Mark.BAR:
        if plot._horizontal:
            return Optional(
                _render_horizontal_bar(
                    target, plot, ox0, oy0, ox1, oy1, cache=cache
                )
            )
        return Optional(
            _render_bar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.SINGLE_AXIS:
        return Optional(
            _render_single_axis(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.ARC:
        return Optional(
            _render_arc(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    return None


def _callback_basic[
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
    """Positional adapter for the stored family callback (#607 prototype)."""
    return _render_basic_family(
        target,
        plot,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
        vector_target=vector_target,
    )
