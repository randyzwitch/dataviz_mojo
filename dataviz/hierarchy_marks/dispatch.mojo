"""Render dispatch for the tree charts (#524).

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
from dataviz.hierarchy_marks.sunburst import _render_sunburst
from dataviz.hierarchy_marks.dendrogram import _render_dendrogram
from dataviz.hierarchy_marks.tree import _render_tree
from dataviz.hierarchy_marks.treemap import _render_treemap


def _render_hierarchy_marks_family[
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
    if plot._mark == Mark.SUNBURST:
        return Optional(
            _render_sunburst(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.TREE:
        return Optional(
            _render_tree(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.DENDROGRAM:
        return Optional(
            _render_dendrogram(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.TREEMAP:
        return Optional(
            _render_treemap(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    return None


def _callback_hierarchy_marks[
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
    return _render_hierarchy_marks_family(
        target,
        plot,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
        vector_target=vector_target,
    )
