"""Render dispatch for the 3D charts (#345).

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
from dataviz.spatial.bar3d import _render_bar3d, _render_voxels
from dataviz.spatial.stem3d import (
    _render_fill_between3d,
    _render_quiver3d,
    _render_stem3d,
)
from dataviz.spatial.scatter3d import _render_plot3d, _render_scatter3d
from dataviz.spatial.surface3d import (
    _render_surface3d,
    _render_trisurf3d,
    _render_wire3d,
)


def _render_spatial_family[
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
    """Render `plot` if it is a 3D mark, else return an empty
    `Optional`.

    Args:
        target: The draw target.
        plot: The chart.
        ox0: Outer left bound.
        oy0: Outer top bound.
        ox1: Outer right bound.
        oy1: Outer bottom bound.
        cache: The render's shared font cache.
        vector_target: Unused here; every mark in this family draws
            the same geometry to every backend.

    Returns:
        The render result, or nothing.

    Raises:
        Error: Whatever the mark's render raises.
    """
    if plot._mark == Mark.SCATTER3D:
        return Optional(
            _render_scatter3d(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.PLOT3D:
        return Optional(
            _render_plot3d(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.SURFACE3D:
        return Optional(
            _render_surface3d(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.WIRE3D:
        return Optional(
            _render_wire3d(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.TRISURF3D:
        return Optional(
            _render_trisurf3d(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.BAR3D:
        return Optional(
            _render_bar3d(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.VOXELS:
        return Optional(
            _render_voxels(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.STEM3D:
        return Optional(
            _render_stem3d(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.QUIVER3D:
        return Optional(
            _render_quiver3d(target, plot, ox0, oy0, ox1, oy1, cache=cache)
        )
    if plot._mark == Mark.FILL_BETWEEN3D:
        return Optional(
            _render_fill_between3d(
                target, plot, ox0, oy0, ox1, oy1, cache=cache
            )
        )
    return None


def _callback_spatial[
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
    return _render_spatial_family(
        target,
        plot,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
        vector_target=vector_target,
    )
