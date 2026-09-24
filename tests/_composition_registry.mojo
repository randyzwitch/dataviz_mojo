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
from canvas.vector.svg import SvgCanvas

from dataviz import (
    render,
    render_svg,
    GridCell,
    Plot,
    Theme,
    clustermap,
    jointplot,
    line,
    pairplot,
    render_facets,
    render_facets_svg,
    render_grid,
    render_grid_svg,
    scatter,
)

comptime _COMPOSITION_COUNT = 6
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
    if index == 5:
        return "mathtext"
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


def _math_plot() raises -> Plot:
    """A scatter whose every label is an expression (#371): a
    superscript and a relation in the title, a fraction on the y
    caption, a subscript on the x caption, Greek in the legend.

    Not a mark, so the mark sweep never renders one; and every backend
    lays the runs out from the same requests, so this is the one place
    the raster and the vector output of an expression are pinned
    against each other and across platforms. On the dark ground for the
    reason the other compositions are: a change that only moves the
    figure background is invisible on white.
    """
    var s = _series()
    var cats = List[String]()
    for i in range(len(s[0])):
        cats.append("$\\mu$" if i % 2 == 0 else "$\\sigma^2$")
    return (
        Plot()
        .mark_point()
        .encode(x=s[0], y=s[1], color_categories=cats)
        .theme(_dark_ground())
        .size(360, 280)
        .labels(
            title="$E = mc^2$",
            x_title="$x_i$ (s)",
            y_title="$\\frac{\\Delta y}{\\Delta x}$",
        )
    )


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
        return render(pairplot(c[0], c[1], cell_width=140, cell_height=120))
    if index == 3:
        var s = _series()
        return render(jointplot(s[0], s[1], width=360, height=360))
    if index == 4:
        return render(clustermap(_matrix(), width=420, height=360))
    if index == 5:
        return render(_math_plot())
    raise Error(
        "_composition_raster(): no composition at index " + String(index)
    )


def _composition_svg(index: Int) raises -> SvgCanvas:
    """Composition `index` rendered to vector, the same figure as
    `_composition_raster`.

    Two functions rather than one returning both, because the facet and
    grid entries render through their own backend-specific functions;
    the composite figures build one `Figure` and render it either way.
    """
    if index == 0:
        return render_facets_svg(_facet_plots(), 2, title="Facets")
    if index == 1:
        return render_grid_svg(
            _grid_plots(), _grid_cells(), 520, 420, align_axes=True
        )
    if index == 2:
        var c = _columns()
        return render_svg(pairplot(c[0], c[1], cell_width=140, cell_height=120))
    if index == 3:
        var s = _series()
        return render_svg(jointplot(s[0], s[1], width=360, height=360))
    if index == 4:
        return render_svg(clustermap(_matrix(), width=420, height=360))
    if index == 5:
        return render_svg(_math_plot())
    raise Error("_composition_svg(): no composition at index " + String(index))
