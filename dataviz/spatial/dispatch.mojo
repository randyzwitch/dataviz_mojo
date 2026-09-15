"""Render dispatch for the 3D charts (#345).

`plot.mojo` calls one entry point per family instead of importing every
mark's render and branching over every `Mark`; see
`dataviz/multivariate/dispatch.mojo` for the pattern and why the "not
mine" answer is an empty `Optional`.
"""

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.mark import Mark
from dataviz.plot import Plot, _RenderResult
from dataviz.spatial.scatter3d import _render_plot3d, _render_scatter3d


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
    `Optional` so the hub tries the next family.

    Args:
        target: The draw target.
        plot: The chart.
        ox0: Outer left bound.
        oy0: Outer top bound.
        ox1: Outer right bound.
        oy1: Outer bottom bound.
        cache: The render's shared font cache.
        vector_target: Unused here; both marks draw the same geometry
            to every backend.

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
    return None
