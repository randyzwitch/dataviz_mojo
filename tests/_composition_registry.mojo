"""One minimal figure per composition: the list the digest sweep walks
alongside `_mark_registry` (#600).

A composition is several charts and a layout, so it has more that can
shift than a single mark does, and its tests tend to assert
relationships -- this cell is left of that one -- rather than exact
output. The per-mark tests are the opposite: many of them pin exact
pixels, so a mark regression has other things that would catch it. That
left the digest strongest where the coverage was already strongest and
silent where it was thinnest, which #588 demonstrated: it deliberately
changed facet rendering, filling the figure background so a partial
last row is not a white hole, and the digest did not notice because
nothing in the sweep renders a facet grid.

**This list is hand-maintained.** `_mark_registry` gets its
completeness from `Mark.COUNT` -- a sweep walks every enum value and
raises for one with no entry, so a new mark cannot be forgotten. There
is no enumeration of compositions to do the same here, so a new
composition function goes uncovered until somebody adds it below.
`_COMPOSITION_COUNT` is the one guard against the list silently
shrinking; it is not a guard against it failing to grow.

Keep the figures small and the data minimal. What the sweep asserts is
about the rendering, not about the data.

One thing here is not minimal on purpose: `_DARK_GROUND`. A figure on
the default light theme cannot see a figure-background change at all,
because the canvas is already white before anything fills it -- which
is exactly why #588's fix was invisible to everything. A digest that
could not see the change it was written for would be worse than no
digest, so the compositions that fill a figure background are rendered
on one that differs from the canvas's starting color.
"""

from canvas.buffer import Canvas
from canvas.color import Color
from canvas.vector.pdf import PdfCanvas
from canvas.vector.svg import SvgCanvas

from dataviz import (
    GridCell,
    Plot,
    Theme,
    clustermap,
    clustermap_pdf,
    clustermap_svg,
    jointplot,
    jointplot_pdf,
    jointplot_svg,
    line,
    pairplot,
    pairplot_pdf,
    pairplot_svg,
    render_facets,
    render_facets_pdf,
    render_facets_svg,
    render_grid,
    render_grid_pdf,
    render_grid_svg,
    scatter,
)

comptime _COMPOSITION_COUNT = 5
"""How many entries `_composition_name` answers for."""


def _dark_ground() -> Theme:
    """A theme whose background is not the color a fresh canvas already
    is, so a figure-background change moves pixels here.

    On the default white theme it does not: `render_facets` fills the
    figure ground before laying out its cells (#568), and on white that
    fill writes white over white. The digest would then hold a figure
    that cannot report the very change the fill exists to make.
    """
    return Theme(background=Color(238, 240, 244))


def _composition_name(index: Int) raises -> String:
    """The digest line's first field, for `index` in
    `[0, _COMPOSITION_COUNT)`."""
    if index == 0:
        return "facets"
    if index == 1:
        return "grid_unequal_aligned"
    if index == 2:
        return "pairplot"
    if index == 3:
        return "jointplot"
    if index == 4:
        return "clustermap"
    raise Error("_composition_name(): no composition at index " + String(index))


def _series() -> Tuple[List[Float64], List[Float64]]:
    """A short x/y pair with no repeated values, so a scatter, a line and
    a histogram of it all have something to draw."""
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(12):
        x.append(Float64(i))
        y.append(Float64((i * 7) % 11) + 1.0)
    return (x^, y^)


def _facet_plots() raises -> List[Plot]:
    """Three cells of the same size -- what `render_facets` requires --
    so the second row is partly empty and the figure ground shows."""
    var s = _series()
    var theme = _dark_ground()
    var plots = List[Plot]()
    plots.append(scatter(s[0], s[1], theme=theme).size(240, 180))
    plots.append(line(s[0], s[1], theme=theme).size(240, 180))
    plots.append(scatter(s[1], s[0], theme=theme).size(240, 180))
    return plots^


def _grid_plots() raises -> List[Plot]:
    """Two charts for the unequal grid below."""
    var s = _series()
    var theme = _dark_ground()
    var plots = List[Plot]()
    plots.append(scatter(s[0], s[1], theme=theme))
    plots.append(line(s[0], s[1], theme=theme))
    return plots^


def _grid_cells() raises -> List[GridCell]:
    """A wide top cell over a narrow one, so the two columns differ and
    `align_axes` has something to align."""
    var cells = List[GridCell]()
    cells.append(GridCell(0, 0, col_span=2))
    cells.append(GridCell(1, 0))
    return cells^


def _columns() -> Tuple[List[List[Float64]], List[String]]:
    """Three short columns for `pairplot`."""
    var cols = List[List[Float64]]()
    var names = List[String]()
    for c in range(3):
        var col = List[Float64]()
        for i in range(12):
            col.append(Float64((i * (c + 3)) % 13))
        cols.append(col^)
        names.append("v" + String(c))
    return (cols^, names^)


def _matrix() -> List[List[Float64]]:
    """A 5x4 matrix with distinguishable rows, for `clustermap`."""
    var out = List[List[Float64]]()
    for r in range(5):
        var row = List[Float64]()
        for c in range(4):
            row.append(Float64((r * 5 + c * 3) % 9))
        out.append(row^)
    return out^


def _composition_raster(index: Int) raises -> Canvas:
    """Composition `index` rendered to pixels."""
    if index == 0:
        return render_facets(_facet_plots(), 2, title="Facets")
    if index == 1:
        return render_grid(
            _grid_plots(), _grid_cells(), 520, 420, align_axes=True
        )
    if index == 2:
        var c = _columns()
        return pairplot(c[0], c[1], cell_width=140, cell_height=120)
    if index == 3:
        var s = _series()
        return jointplot(s[0], s[1], width=360, height=360)
    if index == 4:
        return clustermap(_matrix(), width=420, height=360)
    raise Error(
        "_composition_raster(): no composition at index " + String(index)
    )


def _composition_svg(index: Int) raises -> SvgCanvas:
    """Composition `index` rendered to vector, the same figure as
    `_composition_raster`.

    Two functions rather than one returning both, because each backend's
    entry point takes its own arguments and building the figure twice is
    what the pair of entry points is for.
    """
    if index == 0:
        return render_facets_svg(_facet_plots(), 2, title="Facets")
    if index == 1:
        return render_grid_svg(
            _grid_plots(), _grid_cells(), 520, 420, align_axes=True
        )
    if index == 2:
        var c = _columns()
        return pairplot_svg(c[0], c[1], cell_width=140, cell_height=120)
    if index == 3:
        var s = _series()
        return jointplot_svg(s[0], s[1], width=360, height=360)
    if index == 4:
        return clustermap_svg(_matrix(), width=420, height=360)
    raise Error("_composition_svg(): no composition at index " + String(index))


def _composition_pdf(index: Int) raises -> PdfCanvas:
    """Composition `index` rendered to a one-page PDF, the same figure
    as `_composition_raster` and `_composition_svg`.

    A third entry point per composition rather than a conversion of one
    of the others: that is the whole point of the contract #372 states,
    that nothing is resampled on the way out.
    """
    if index == 0:
        return render_facets_pdf(_facet_plots(), 2, title="Facets")
    if index == 1:
        return render_grid_pdf(
            _grid_plots(), _grid_cells(), 520, 420, align_axes=True
        )
    if index == 2:
        var c = _columns()
        return pairplot_pdf(c[0], c[1], cell_width=140, cell_height=120)
    if index == 3:
        var s = _series()
        return jointplot_pdf(s[0], s[1], width=360, height=360)
    if index == 4:
        return clustermap_pdf(_matrix(), width=420, height=360)
    raise Error("_composition_pdf(): no composition at index " + String(index))
