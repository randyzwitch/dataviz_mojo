"""Render dispatch for the one-categorical-dimension charts (#524).

Each `Plot.mark_*()` setter registers this family's callback for Canvas,
SVG, PDF, and BoundsTarget. `_render_generic` invokes the selected callback rather than
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
from dataviz.categorical.bullet import _render_bullet
from dataviz.categorical.bump import _render_bump
from dataviz.categorical.funnel import _render_funnel
from dataviz.categorical.gantt import _render_gantt
from dataviz.categorical.grouped_bar import (
    _render_grouped_bar,
    _render_horizontal_grouped_bar,
)
from dataviz.categorical.lollipop import (
    _render_horizontal_lollipop,
    _render_lollipop,
)
from dataviz.categorical.population_pyramid import _render_population_pyramid
from dataviz.categorical.span_chart import _render_span_chart
from dataviz.categorical.stacked_bar import (
    _render_horizontal_stacked_bar,
    _render_stacked_bar,
)
from dataviz.categorical.streamgraph import _render_streamgraph
from dataviz.categorical.waterfall import _render_waterfall


def _render_categorical_family[
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
    if plot._mark == Mark.LOLLIPOP:
        if plot._horizontal:
            return Optional(
                _render_horizontal_lollipop(
                    target, plot, ox0, oy0, ox1, oy1, cache=cache
                )
            )
        return Optional(
            _render_lollipop(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.WATERFALL:
        return Optional(
            _render_waterfall(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.BULLET:
        return Optional(
            _render_bullet(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.GROUPED_BAR:
        if plot._horizontal:
            return Optional(
                _render_horizontal_grouped_bar(
                    target, plot, ox0, oy0, ox1, oy1, cache=cache
                )
            )
        return Optional(
            _render_grouped_bar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.STACKED_BAR:
        if plot._horizontal:
            return Optional(
                _render_horizontal_stacked_bar(
                    target, plot, ox0, oy0, ox1, oy1, cache=cache
                )
            )
        return Optional(
            _render_stacked_bar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.GANTT:
        return Optional(
            _render_gantt(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.SPAN_CHART:
        return Optional(
            _render_span_chart(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.POPULATION_PYRAMID:
        return Optional(
            _render_population_pyramid(
                target, plot, ox0, oy0, ox1, oy1, cache=cache
            )
        )
    if plot._mark == Mark.FUNNEL:
        return Optional(
            _render_funnel(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.BUMP:
        return Optional(
            _render_bump(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.STREAMGRAPH:
        return Optional(
            _render_streamgraph(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    return None


def _callback_categorical[
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
    return _render_categorical_family(
        target,
        plot,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
        vector_target=vector_target,
    )
