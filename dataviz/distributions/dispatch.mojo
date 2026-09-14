"""Render dispatch for the distribution shapes (#524).

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
from dataviz.distributions.beeswarm import (
    _render_beeswarm,
    _render_horizontal_beeswarm,
)
from dataviz.distributions.box import _render_box, _render_horizontal_box
from dataviz.distributions.boxen import (
    _render_boxenplot,
    _render_horizontal_boxenplot,
)
from dataviz.distributions.candlestick import _render_candlestick
from dataviz.distributions.ecdf import _render_ecdf
from dataviz.distributions.eventplot import _render_eventplot
from dataviz.distributions.kde import _render_kde, _render_rug
from dataviz.distributions.ridgeline import _render_ridgeline
from dataviz.distributions.violin import (
    _render_horizontal_violin,
    _render_violin,
)


def _render_distributions_family[
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
    if plot._mark == Mark.BOXENPLOT:
        if plot._horizontal:
            return Optional(
                _render_horizontal_boxenplot(
                    target, plot, ox0, oy0, ox1, oy1, cache=cache
                )
            )
        return Optional(
            _render_boxenplot(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.BOX:
        if plot._horizontal:
            return Optional(
                _render_horizontal_box(
                    target, plot, ox0, oy0, ox1, oy1, cache=cache
                )
            )
        return Optional(
            _render_box(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.CANDLESTICK:
        return Optional(
            _render_candlestick(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.KDE:
        return Optional(
            _render_kde(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.RUG:
        return Optional(
            _render_rug(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.EVENTPLOT:
        return Optional(
            _render_eventplot(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.ECDF:
        return Optional(
            _render_ecdf(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.BEESWARM:
        if plot._horizontal:
            return Optional(
                _render_horizontal_beeswarm(
                    target, plot, ox0, oy0, ox1, oy1, cache=cache
                )
            )
        return Optional(
            _render_beeswarm(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.VIOLIN:
        if plot._horizontal:
            return Optional(
                _render_horizontal_violin(
                    target, plot, ox0, oy0, ox1, oy1, cache=cache
                )
            )
        return Optional(
            _render_violin(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.RIDGELINE:
        return Optional(
            _render_ridgeline(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    return None


def _callback_distributions[
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
    return _render_distributions_family(
        target,
        plot,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
        vector_target=vector_target,
    )
