"""Unequal-cell figure composition: matplotlib's gridspec (#347).

`render_facets()` gives a uniform grid and `render_layers()` gives a full
overlay. Neither says "a wide time series above two narrow detail
panels", which is most of what a report or a dashboard is.

`render_grid()` places each plot at a row and column with optional spans,
over a grid whose rows and columns can carry weights, so a 2:1 split is
expressible. Every cell is an independent render into its own rect,
exactly as a facet cell already is; what is new is saying where the rects
go.

`render_facets()` is deliberately left alone rather than reimplemented on
top of this. It is load-bearing, `pairplot()` sits on it, and its
shared-scale logic is subtle. Rewriting a working path to prove a new one
is how a regression arrives with nothing to attribute it to. Folding the
two together is worth doing once this has been exercised by something
other than its own tests.

Insets are not here either. #347 treats them as a separate entry point on
purpose: an inset is an overlay, not a cell, and folding it into the grid
model would distort both.
"""

from canvas.buffer import Canvas
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.text import (
    _TextRequest,
    _apply_labels,
    _extend_text_requests,
    _label_text_requests,
    _replay_text_requests,
)
from dataviz.plot import Plot, _render_generic, _resolve_supersample


struct GridCell(Copyable, ImplicitlyCopyable, Movable):
    """Where one plot sits: a row and column, and how many of each it
    spans.

    Spans default to 1, so the common case reads as a coordinate pair
    and only an unequal layout has to say more.
    """

    var row: Int
    var col: Int
    var row_span: Int
    var col_span: Int

    def __init__(
        out self, row: Int, col: Int, row_span: Int = 1, col_span: Int = 1
    ):
        """Place a plot.

        Args:
            row: Top row, from 0.
            col: Left column, from 0.
            row_span: How many rows it covers.
            col_span: How many columns it covers.
        """
        self.row = row
        self.col = col
        self.row_span = row_span
        self.col_span = col_span


def _weighted_edges(
    total: Int, weights: List[Float64], n: Int
) raises -> List[Int]:
    """Pixel boundaries for `n` tracks across `total` pixels.

    Edges are cumulative and rounded once from the running sum rather
    than by accumulating rounded widths, so the tracks always add up to
    `total` exactly and adjacent cells share a boundary pixel. That is
    the property `render_facets()` gets from `width * col // cols`.

    Args:
        total: Pixels to divide.
        weights: One weight per track, or empty for equal tracks.
        n: How many tracks.

    Returns:
        `n + 1` boundaries, starting at 0 and ending at `total`.

    Raises:
        Error: A weight count that does not match, or a non-positive
            weight.
    """
    var w = List[Float64](capacity=n)
    if len(weights) == 0:
        for _ in range(n):
            w.append(1.0)
    else:
        if len(weights) != n:
            raise Error(
                "render_grid(): expected "
                + String(n)
                + " weights to match the grid, got "
                + String(len(weights))
            )
        for i in range(len(weights)):
            if weights[i] <= 0.0:
                raise Error(
                    "render_grid(): weight "
                    + String(i)
                    + " is "
                    + String(weights[i])
                    + ", but a track with no width cannot hold a plot"
                )
            w.append(weights[i])

    var sum = 0.0
    for v in w:
        sum += v
    var edges = List[Int](capacity=n + 1)
    edges.append(0)
    var running = 0.0
    for i in range(n):
        running += w[i]
        edges.append(Int(running / sum * Float64(total) + 0.5))
    edges[n] = total
    return edges^


def _check_cells(cells: List[GridCell], rows: Int, cols: Int) raises:
    """No cell may fall outside the grid or overlap another (#347).

    Both raise rather than draw. An out-of-range cell would be silently
    clipped and an overlap would paint one plot over another, and in
    both cases the figure looks deliberate.

    Args:
        cells: One per plot.
        rows: Grid height.
        cols: Grid width.

    Raises:
        Error: A cell outside the grid, a non-positive span, or two
            cells sharing a square.
    """
    var occupied = List[Int](capacity=rows * cols)
    for _ in range(rows * cols):
        occupied.append(-1)
    for i in range(len(cells)):
        var c = cells[i]
        if c.row_span < 1 or c.col_span < 1:
            raise Error(
                "render_grid(): plot "
                + String(i)
                + " spans "
                + String(c.row_span)
                + " rows and "
                + String(c.col_span)
                + " columns; both must be at least 1"
            )
        if c.row < 0 or c.col < 0:
            raise Error(
                "render_grid(): plot "
                + String(i)
                + " is at row "
                + String(c.row)
                + ", column "
                + String(c.col)
                + "; neither may be negative"
            )
        if c.row + c.row_span > rows or c.col + c.col_span > cols:
            raise Error(
                "render_grid(): plot "
                + String(i)
                + " covers rows "
                + String(c.row)
                + " to "
                + String(c.row + c.row_span - 1)
                + " and columns "
                + String(c.col)
                + " to "
                + String(c.col + c.col_span - 1)
                + ", which is outside the "
                + String(rows)
                + " by "
                + String(cols)
                + " grid"
            )
        for r in range(c.row, c.row + c.row_span):
            for k in range(c.col, c.col + c.col_span):
                var at = r * cols + k
                if occupied[at] != -1:
                    raise Error(
                        "render_grid(): plot "
                        + String(i)
                        + " overlaps plot "
                        + String(occupied[at])
                        + " at row "
                        + String(r)
                        + ", column "
                        + String(k)
                    )
                occupied[at] = i


def _grid_shape(cells: List[GridCell]) -> Tuple[Int, Int]:
    """The smallest grid the cells fit in.

    Inferred rather than asked for: the caller already said where every
    plot goes, and a separate `rows`/`cols` argument could disagree with
    that, which is one more thing to validate and get wrong.

    Args:
        cells: One per plot.

    Returns:
        `(rows, cols)`.
    """
    var rows = 0
    var cols = 0
    for i in range(len(cells)):
        var r = cells[i].row + cells[i].row_span
        var c = cells[i].col + cells[i].col_span
        if r > rows:
            rows = r
        if c > cols:
            cols = c
    return (rows, cols)


def render_grid(
    plots: List[Plot],
    cells: List[GridCell],
    width: Int,
    height: Int,
    row_weights: List[Float64] = List[Float64](),
    col_weights: List[Float64] = List[Float64](),
) raises -> Canvas:
    """Render `plots` into unequal cells of one canvas (#347).

    matplotlib's gridspec model: each plot names a row, a column and
    optional spans, over a grid whose rows and columns can carry
    weights. `render_facets()` is the degenerate case of equal weights
    and one cell each.

    The canvas is `width` by `height` and the cells divide it, rather
    than the canvas being sized from the plots as `render_facets()` does.
    A grid of unequal cells has no single plot size to multiply, and a
    caller composing a report is usually working to a fixed output size
    anyway.

    Each plot's own `width`/`height` are therefore ignored for layout.
    They still matter for `Theme.scale`-independent sizing inside the
    cell, which is what `_apply_labels` reads.

    Args:
        plots: The charts, one per entry in `cells`.
        cells: Where each plot goes.
        width: Canvas width in pixels.
        height: Canvas height.
        row_weights: Relative row heights, or empty for equal rows.
        col_weights: Relative column widths, or empty for equal columns.

    Returns:
        The rendered canvas.

    Raises:
        Error: Mismatched `plots`/`cells`, an empty figure, a
            non-positive canvas, a cell outside the grid, overlapping
            cells, or a bad weight.
    """
    if len(plots) != len(cells):
        raise Error(
            "render_grid(): one cell per plot, so "
            + String(len(plots))
            + " -- got "
            + String(len(cells))
        )
    if len(plots) == 0:
        raise Error("render_grid(): nothing to draw")
    if width <= 0 or height <= 0:
        raise Error(
            "render_grid(): canvas must be positive, got "
            + String(width)
            + " by "
            + String(height)
        )

    var shape = _grid_shape(cells)
    var rows = shape[0]
    var cols = shape[1]
    _check_cells(cells, rows, cols)

    var x_edges = _weighted_edges(width, col_weights, cols)
    var y_edges = _weighted_edges(height, row_weights, rows)

    # One canvas, one supersample factor, chosen the way render_facets
    # does: the largest any plot asks for, so a curved mark beside a bar
    # chart is not drawn at the bar's factor.
    var factor = _resolve_supersample(plots[0], "render_grid")
    for i in range(len(plots)):
        var f = _resolve_supersample(plots[i], "render_grid")
        if f > factor:
            factor = f

    var canvas = Canvas(width, height, plots[0]._theme.background)
    canvas.begin_supersampled(factor, plots[0]._theme.background)
    var cache = FontCache()
    var text_requests = List[_TextRequest]()

    for i in range(len(plots)):
        var c = cells[i]
        var cx0 = x_edges[c.col]
        var cx1 = x_edges[c.col + c.col_span]
        var cy0 = y_edges[c.row]
        var cy1 = y_edges[c.row + c.row_span]
        canvas.fill_rect(
            cx0, cy0, cx1 - cx0, cy1 - cy0, plots[i]._theme.background
        )
        var frame = _apply_labels(plots[i], cx0, cy0, cx1, cy1)
        var cell_result = _render_generic(
            canvas,
            plots[i],
            frame.ox0,
            frame.oy0,
            frame.ox1,
            frame.oy1,
            cache=cache,
        )
        _extend_text_requests(text_requests, cell_result.text_requests)
        _extend_text_requests(
            text_requests,
            _label_text_requests(
                plots[i],
                cx0,
                cy0,
                cx1,
                cy1,
                cell_result.px0,
                cell_result.py0,
                cell_result.px1,
                cell_result.py1,
            ),
        )

    _replay_text_requests(canvas, text_requests, cache)
    canvas.end_supersampled()
    return canvas^
