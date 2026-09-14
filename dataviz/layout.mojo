"""Cell layout: the one core `render_facets()` and `render_grid()` share.

A figure made of cells is one idea with two faces. `render_facets()` is
the uniform one: `n` plots, `cols` per row, every cell the same size.
`render_grid()` is matplotlib's gridspec: each plot names a row, a column
and optional spans, over tracks that can carry weights, so "a wide time
series above two narrow detail panels" is expressible (#347).

Both come through `_render_cells_generic()`. A facet grid is the
degenerate case -- one cell per plot, equal weights -- so there is one
implementation of the hard parts: the shared y-domain, the gutter between
stacked rows, and the six per-cell annotation passes.

One core rather than two is the whole point. A second cell loop written
alongside the first is a subset of it by default: it renders the marks,
which is the visible part, and quietly omits the parts nobody looked at
yet. Vector output and per-cell annotations are both in that category,
and neither absence would show up in a screenshot.

Insets are not here. #347 treats them as a separate entry point on
purpose: an inset is an overlay, not a cell, and folding it into the grid
model would distort both.
"""

from canvas.buffer import Canvas
from canvas.io.bmp import write_bmp
from canvas.io.png import write_png
from canvas.text.font_cache import FontCache
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget
from canvas.vector.svg import SvgCanvas

from dataviz.core.annotations import (
    _draw_annotation_areas,
    _draw_annotation_bands,
    _draw_annotation_best_fit,
    _draw_annotation_lines,
    _draw_annotation_points,
    _draw_annotation_vlines,
)
from dataviz.core.mark import Mark
from dataviz.core.theme import Theme
from dataviz.core.output_format import OutputFormat
from dataviz.core.text import (
    _Scaled,
    _TextRequest,
    _apply_labels,
    _extend_text_requests,
    _label_text_requests,
    _replay_text_requests,
    _replay_text_requests_svg,
)
from dataviz.plot import (
    Plot,
    _data_extent,
    _filled_annotations_go_under,
    _log_data_extent,
    _render_generic,
    _resolve_output_format,
    _resolve_supersample,
    _svg_output_string,
    _zero_baseline_y_extent,
)


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


def _figure_title_band(theme: Theme, title: String) -> Int:
    """The strip a figure title reserves above the cells: zero for no
    title, else the same band a chart's own title takes in
    `_apply_labels`, so a figure title and a chart title sit at the same
    height and in the same face. `theme` is the figure's, which is
    `plots[0]`'s everywhere a figure has one.
    """
    if title.byte_length() == 0:
        return 0
    var sc = _Scaled(theme)
    return Int(sc.title_font_size) + sc.label_gap


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
    var edges = List[Int](capacity=n + 1)
    if len(weights) == 0:
        # Integer arithmetic, not 1.0/n repeated: this is the exact
        # expression render_facets() used before it moved here, and a
        # float round trip does not always land on the same pixel
        # (3 tracks across 100 puts the second edge at 66 by floor and
        # 67 by rounding). Facet output has to be unchanged.
        for i in range(n + 1):
            edges.append(total * i // n)
        return edges^

    if len(weights) != n:
        raise Error(
            "render_grid(): expected "
            + String(n)
            + " weights to match the grid, got "
            + String(len(weights))
        )
    var w = List[Float64](capacity=n)
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


def _measure_alignment_insets(
    plots: List[Plot],
    cells: List[GridCell],
    x_edges: List[Int],
    y_edges: List[Int],
    gutter: Int,
    rows: Int,
    cols: Int,
    shared_y_scale: Bool,
    shared_y_min: Float64,
    shared_y_max: Float64,
    shared_y_is_log: Bool,
    width: Int,
    height: Int,
    mut inset_left: List[Int],
    mut inset_right: List[Int],
    mut inset_top: List[Int],
    mut inset_bottom: List[Int],
) raises:
    """Work out how far to inset each cell so a column shares its plot
    rect's left and right edges, and a row its top and bottom (#569).

    Measured rather than predicted. Each cell is rendered once into a
    scratch canvas and asked where its plot rect actually landed, which
    is the only way to know: a margin comes from the width of tick
    labels this library chose, and predicting those means reimplementing
    the tick selection.

    A spanning cell takes part in the column it starts in and the column
    it ends in, which are the only two edges a span has.

    The scratch is a raster canvas whatever the real target is, because
    a margin comes from `measure_text` and does not depend on the
    backend. Its own font cache is thrown away with it; the real render
    builds its own, and sharing one would mean the measure pass decided
    what the draw pass had cached.

    Args:
        plots: The charts.
        cells: Where each goes.
        x_edges: Column boundaries.
        y_edges: Row boundaries.
        gutter: Height taken off every cell's bottom.
        rows: Grid height.
        cols: Grid width.
        shared_y_scale: Whether a shared y-domain is in force.
        shared_y_min: Its low end.
        shared_y_max: Its high end.
        shared_y_is_log: Whether it is logarithmic.
        width: Figure width, for the scratch.
        height: Figure height.
        inset_left: Filled in, one per plot.
        inset_right: Filled in.
        inset_top: Filled in.
        inset_bottom: Filled in.

    Raises:
        Error: Whatever rendering a cell raises. A figure that cannot be
            measured cannot be drawn either, so this surfaces the same
            error one pass earlier.
    """
    var own_left = List[Int](capacity=len(plots))
    var own_right = List[Int](capacity=len(plots))
    var own_top = List[Int](capacity=len(plots))
    var own_bottom = List[Int](capacity=len(plots))

    var scratch = Canvas(width, height)
    var scratch_cache = FontCache()
    for i in range(len(plots)):
        var c = cells[i]
        var cell_x0 = x_edges[c.col]
        var cell_x1 = x_edges[c.col + c.col_span]
        var cell_y0 = y_edges[c.row]
        var cell_y1 = y_edges[c.row + c.row_span] - gutter
        var frame = _apply_labels(plots[i], cell_x0, cell_y0, cell_x1, cell_y1)
        var probe = _render_generic(
            scratch,
            plots[i],
            frame.ox0,
            frame.oy0,
            frame.ox1,
            frame.oy1,
            has_shared_y_domain=shared_y_scale,
            shared_y_min=shared_y_min,
            shared_y_max=shared_y_max,
            shared_y_is_log=shared_y_is_log,
            cache=scratch_cache,
        )
        own_left.append(probe.px0 - cell_x0)
        own_right.append(cell_x1 - probe.px1)
        own_top.append(probe.py0 - cell_y0)
        own_bottom.append(cell_y1 - probe.py1)

    var col_left = List[Int](capacity=cols)
    var col_right = List[Int](capacity=cols)
    for _ in range(cols):
        col_left.append(0)
        col_right.append(0)
    var row_top = List[Int](capacity=rows)
    var row_bottom = List[Int](capacity=rows)
    for _ in range(rows):
        row_top.append(0)
        row_bottom.append(0)

    for i in range(len(plots)):
        var c = cells[i]
        var last_col = c.col + c.col_span - 1
        var last_row = c.row + c.row_span - 1
        if own_left[i] > col_left[c.col]:
            col_left[c.col] = own_left[i]
        if own_right[i] > col_right[last_col]:
            col_right[last_col] = own_right[i]
        if own_top[i] > row_top[c.row]:
            row_top[c.row] = own_top[i]
        if own_bottom[i] > row_bottom[last_row]:
            row_bottom[last_row] = own_bottom[i]

    for i in range(len(plots)):
        var c = cells[i]
        inset_left[i] = col_left[c.col] - own_left[i]
        inset_right[i] = col_right[c.col + c.col_span - 1] - own_right[i]
        inset_top[i] = row_top[c.row] - own_top[i]
        inset_bottom[i] = row_bottom[c.row + c.row_span - 1] - own_bottom[i]


def _render_cells_generic[
    T: DrawTarget
](
    mut target: T,
    width: Int,
    height: Int,
    plots: List[Plot],
    cells: List[GridCell],
    row_weights: List[Float64] = List[Float64](),
    col_weights: List[Float64] = List[Float64](),
    shared_y_scale: Bool = False,
    align_axes: Bool = False,
    title: String = "",
    *,
    mut cache: FontCache,
) raises -> List[_TextRequest]:
    """The one cell-layout core. `render_facets()` and `render_grid()`
    both call it; a uniform facet grid is the degenerate case of one cell
    each and equal weights (#347).

    Each cell is laid out as a standalone render into its own rect, which
    is what gives a cell its own axis frame, legend, annotations and
    best-fit line without any of them knowing they are in a grid.

    `shared_y_scale` gives every cell one y-domain, computed once here so
    every cell reads the same two numbers. Only the continuous marks
    support it; `_render_generic` raises per cell for the rest, including
    a log/linear mix, so the error names the cell that disagrees.

    `align_axes` is its pixel counterpart (#569). A shared domain puts
    two cells on the same numbers; it does not put them on the same
    pixels, because each cell sizes its own margins from its own tick
    labels and those are rarely the same width. For a facet grid that
    hardly matters, since every cell shows the same kind of number. For a
    joint plot it is the whole feature: the marginal above a scatter
    counts observations while the scatter shows the data, so their
    y-labels differ in width, and a marginal offset from the panel it
    describes is lying about where the mass is.

    It works by measuring rather than by predicting. Every cell is
    rendered once into a scratch canvas and asked where its plot rect
    actually landed; the widest left margin in a column, and the widest
    right, become that column's, and likewise top and bottom per row.
    The draw pass then hands each cell a rect inset by the difference
    between its column's margin and its own, so every plot rect in the
    column lands on the same edges. Margins do not depend on where a rect
    starts, only on its size and content, which is what makes the
    arithmetic hold.

    The measure pass costs a second full render, so it happens only when
    asked for. It uses a raster scratch whatever `T` is, because a
    margin comes from `measure_text` and is the same either way.

    Args:
        target: The draw target, raster or vector.
        width: Figure width in pixels.
        height: Figure height.
        plots: The charts.
        cells: Where each plot goes, one per plot.
        row_weights: Relative row heights, empty for equal.
        col_weights: Relative column widths, empty for equal.
        shared_y_scale: One y-domain across every cell.
        align_axes: Give every cell in a column the same left and right
            plot-rect edges, and every cell in a row the same top and
            bottom.
        title: A figure title, centered above every cell in the band
            `_figure_title_band` reserves; the cells share what is left
            of `height`. Empty draws nothing and reserves nothing.
        cache: The figure's shared font cache.

    Returns:
        Every text request the cells produced, for one replay pass.

    Raises:
        Error: A bad cell or weight, or anything `_render_generic` raises
            for a cell.
    """
    var text_requests = List[_TextRequest]()
    if len(plots) == 0:
        return text_requests^

    var shape = _grid_shape(cells)
    var rows = shape[0]
    var cols = shape[1]
    _check_cells(cells, rows, cols)
    # A figure title takes a band off the top and the cells tile what
    # remains, so the tracks still add up to the canvas exactly.
    var band = _figure_title_band(plots[0]._theme, title)
    var x_edges = _weighted_edges(width, col_weights, cols)
    var y_edges = _weighted_edges(height - band, row_weights, rows)
    if band > 0:
        for k in range(len(y_edges)):
            y_edges[k] += band
        var theme = plots[0]._theme
        var sc = _Scaled(theme)
        text_requests.append(
            _TextRequest(
                width // 2,
                Int(sc.title_font_size * 0.8),
                title,
                theme.text_color,
                sc.title_font_size,
                TextAlign.CENTER,
                theme.font_family,
                bold=theme.title_bold,
            )
        )

    # Computed once up front when asked for, so every cell reads the same
    # two numbers. shared_y_is_log follows plots[0]; a mix raises inside
    # _render_generic's own per-cell check rather than here, so the error
    # names which cell disagrees.
    var shared_y_min = 0.0
    var shared_y_max = 0.0
    var shared_y_is_log = shared_y_scale and plots[0]._y_log
    if shared_y_scale:
        var combined_y = List[Float64]()
        for i in range(len(plots)):
            for v in plots[i]._continuous.y:
                combined_y.append(v)
        # A Mark.AREA cell anywhere forces the zero baseline for the whole
        # grid, the rule render_layers() applies to an axis group: an
        # area's height is measured from a baseline, so a shared domain
        # that floats above zero would draw every cell's fill from a
        # different, meaningless floor.
        var any_area = False
        for i in range(len(plots)):
            if plots[i]._mark == Mark.AREA or (
                plots[i]._mark == Mark.HISTOGRAM
                and not plots[i]._histogram.horizontal
            ):
                any_area = True
        var domain = _log_data_extent(combined_y) if shared_y_is_log else (
            _zero_baseline_y_extent(combined_y) if any_area else _data_extent(
                combined_y
            )
        )
        shared_y_min = domain.domain_min
        shared_y_max = domain.domain_max

    # Cells tile edge to edge, so a cell's x-axis title lands directly
    # against the next row's chart title. Zero unless the figure actually
    # has that collision, so a single row renders exactly as before.
    var wants_gutter = rows > 1
    if wants_gutter:
        var any_x_title = False
        var any_title = False
        for i in range(len(plots)):
            if plots[i]._labels.x_title.byte_length() > 0:
                any_x_title = True
            if plots[i]._labels.title.byte_length() > 0:
                any_title = True
        wants_gutter = any_x_title and any_title
    var gutter = Int(
        _Scaled(plots[0]._theme).label_gap * 2
    ) if wants_gutter else 0

    # How far each cell's own rect is inset to bring its plot rect onto
    # its column's and row's shared edges. All zero unless align_axes.
    var inset_left = List[Int](capacity=len(plots))
    var inset_right = List[Int](capacity=len(plots))
    var inset_top = List[Int](capacity=len(plots))
    var inset_bottom = List[Int](capacity=len(plots))
    for _ in range(len(plots)):
        inset_left.append(0)
        inset_right.append(0)
        inset_top.append(0)
        inset_bottom.append(0)
    if align_axes:
        _measure_alignment_insets(
            plots,
            cells,
            x_edges,
            y_edges,
            gutter,
            rows,
            cols,
            shared_y_scale,
            shared_y_min,
            shared_y_max,
            shared_y_is_log,
            width,
            height,
            inset_left,
            inset_right,
            inset_top,
            inset_bottom,
        )

    for i in range(len(plots)):
        var c = cells[i]
        var cell_x0 = x_edges[c.col]
        var cell_x1 = x_edges[c.col + c.col_span]
        var cell_y0 = y_edges[c.row]
        var cell_y1 = y_edges[c.row + c.row_span]
        # Each cell's full rect is filled with that cell's background,
        # including the strip a title's margin reserves.
        target.fill_rect(
            cell_x0,
            cell_y0,
            cell_x1 - cell_x0,
            cell_y1 - cell_y0,
            plots[i]._theme.background,
        )
        var cell_content_y1 = cell_y1 - gutter
        # The inset rect the cell actually lays out in. Identical to the
        # cell rect unless align_axes asked for shared edges.
        var laid_x0 = cell_x0 + inset_left[i]
        var laid_x1 = cell_x1 - inset_right[i]
        var laid_y0 = cell_y0 + inset_top[i]
        var laid_y1 = cell_content_y1 - inset_bottom[i]
        var frame = _apply_labels(plots[i], laid_x0, laid_y0, laid_x1, laid_y1)
        var cell_result = _render_generic(
            target,
            plots[i],
            frame.ox0,
            frame.oy0,
            frame.ox1,
            frame.oy1,
            has_shared_y_domain=shared_y_scale,
            shared_y_min=shared_y_min,
            shared_y_max=shared_y_max,
            shared_y_is_log=shared_y_is_log,
            cache=cache,
        )
        var label_requests = _label_text_requests(
            plots[i],
            cell_x0,
            cell_y0,
            cell_x1,
            cell_content_y1,
            cell_result.px0,
            cell_result.py0,
            cell_result.px1,
            cell_result.py1,
        )
        # Each cell's annotations draw against that cell's own x/y scale,
        # in the same order a standalone render uses (areas and bands
        # underneath, then lines/vlines, points on top, best_fit last).
        var cell_under = _filled_annotations_go_under(plots[i]._mark)
        var cell_area_requests = List[
            _TextRequest
        ]() if cell_under else _draw_annotation_areas(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_band_requests = List[
            _TextRequest
        ]() if cell_under else _draw_annotation_bands(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_vline_requests = _draw_annotation_vlines(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_line_requests = _draw_annotation_lines(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_point_requests = _draw_annotation_points(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_best_fit_requests = _draw_annotation_best_fit(
            target, plots[i], cell_result, plots[i]._theme
        )
        _extend_text_requests(text_requests, label_requests)
        _extend_text_requests(text_requests, cell_area_requests)
        _extend_text_requests(text_requests, cell_band_requests)
        _extend_text_requests(text_requests, cell_vline_requests)
        _extend_text_requests(text_requests, cell_line_requests)
        _extend_text_requests(text_requests, cell_point_requests)
        _extend_text_requests(text_requests, cell_best_fit_requests)
        _extend_text_requests(text_requests, cell_result.text_requests)

    return text_requests^


def uniform_cells(count: Int, cols: Int) raises -> List[GridCell]:
    """`count` plots left to right, `cols` per row: what a facet grid is.

    Args:
        count: How many plots.
        cols: Cells per row.

    Returns:
        One cell per plot.

    Raises:
        Error: `cols` is not positive.
    """
    if cols <= 0:
        raise Error(
            "uniform_cells(): cols must be positive (got " + String(cols) + ")"
        )
    var cells = List[GridCell](capacity=count)
    for i in range(count):
        cells.append(GridCell(i // cols, i % cols))
    return cells^


def _check_grid_args(
    plots: List[Plot], cells: List[GridCell], caller: String
) raises:
    """`render_grid()`'s shared preconditions, before any layout math.

    Args:
        plots: The charts.
        cells: Where each one goes.
        caller: The entry point to name in an error.

    Raises:
        Error: No plots, or a cell count that does not match.
    """
    if len(plots) == 0:
        raise Error(caller + "(): nothing to draw -- plots is empty")
    if len(cells) != len(plots):
        raise Error(
            caller
            + "(): expected one cell per plot, got "
            + String(len(cells))
            + " cells for "
            + String(len(plots))
            + " plots"
        )


def render_grid(
    plots: List[Plot],
    cells: List[GridCell],
    width: Int,
    height: Int,
    row_weights: List[Float64] = List[Float64](),
    col_weights: List[Float64] = List[Float64](),
    shared_y_scale: Bool = False,
    align_axes: Bool = False,
    title: String = "",
) raises -> Canvas:
    """Place each plot in its own cell of one `width` by `height` canvas.

    The figure size is given rather than derived from the plots, because
    unequal cells have no single plot size to derive it from. Each
    plot's own `.size()` is ignored; its cell's rect is what it renders
    into.

    ```mojo
    from dataviz import GridCell, Plot, render_grid
    from canvas.io.png import write_png

    def main():
        var x = List[Float64](0.0, 1.0, 2.0, 3.0)
        var top = Plot().mark_line().encode(x=x, y=List[Float64](1.0, 4.0, 2.0, 5.0))
        var left = Plot().mark_point().encode(x=x, y=List[Float64](2.0, 1.0, 3.0, 2.0))
        var right = Plot().mark_bar().encode(x=x, y=List[Float64](3.0, 1.0, 2.0, 4.0))

        var plots = List[Plot](top, left, right)
        var cells = List[GridCell](
            GridCell(0, 0, col_span=2), GridCell(1, 0), GridCell(1, 1)
        )
        var rows = List[Float64](2.0, 1.0)
        write_png(render_grid(plots, cells, 800, 600, row_weights=rows), "grid.png")
    ```

    Args:
        plots: The charts, one per cell.
        cells: Where each plot goes.
        width: Figure width in pixels.
        height: Figure height in pixels.
        row_weights: Relative row heights, empty for equal rows.
        col_weights: Relative column widths, empty for equal columns.
        shared_y_scale: Give every cell one y-domain.
        align_axes: Share plot-rect edges down each column and across
            each row, so a cell lines up with its neighbors rather than
            with whatever its own tick labels happened to need (#569).
            Costs a second measuring render.
        title: A figure title, centered above the cells, which share
            the height left under it. Empty for none.

    Returns:
        The rendered figure.

    Raises:
        Error: An empty figure, a cell count that does not match, an
            overlapping or out-of-range cell, or a bad weight.
    """
    _check_grid_args(plots, cells, "render_grid")
    # One canvas, so one factor must serve every plot on it: take the
    # largest any of them asks for, as render_facets() does.
    var factor = _resolve_supersample(plots[0], "render_grid")
    for i in range(1, len(plots)):
        var f = _resolve_supersample(plots[i], "render_grid")
        if f > factor:
            factor = f
    var canvas = Canvas(width, height)
    canvas.begin_supersampled(factor)
    # A grid may leave a square empty on purpose -- the corner opposite a
    # joint plot's two marginals is the standard case -- and an unpainted
    # square is white, which is a hole in any theme that is not. Filled
    # before the cells so each cell's own fill still wins; with no gaps
    # this is entirely overdrawn.
    canvas.fill_rect(0, 0, width, height, plots[0]._theme.background)
    var cache = FontCache()
    var text_requests = _render_cells_generic(
        canvas,
        width,
        height,
        plots,
        cells,
        row_weights,
        col_weights,
        shared_y_scale,
        align_axes,
        title,
        cache=cache,
    )
    _replay_text_requests(canvas, text_requests, cache)
    canvas.end_supersampled()
    return canvas^


def render_grid_svg(
    plots: List[Plot],
    cells: List[GridCell],
    width: Int,
    height: Int,
    row_weights: List[Float64] = List[Float64](),
    col_weights: List[Float64] = List[Float64](),
    shared_y_scale: Bool = False,
    align_axes: Bool = False,
    title: String = "",
) raises -> SvgCanvas:
    """`render_grid()`'s counterpart for `SvgCanvas`.

    Args:
        plots: The charts, one per cell.
        cells: Where each plot goes.
        width: Figure width.
        height: Figure height.
        row_weights: Relative row heights, empty for equal rows.
        col_weights: Relative column widths, empty for equal columns.
        shared_y_scale: Give every cell one y-domain.
        align_axes: Share plot-rect edges, as `render_grid()`.
        title: A figure title above the cells, as `render_grid()`.

    Returns:
        The rendered figure as vector markup.

    Raises:
        Error: Whatever `render_grid()` raises.
    """
    _check_grid_args(plots, cells, "render_grid_svg")
    var svg = SvgCanvas(width, height)
    # See render_grid(): an empty square is a hole without this.
    svg.fill_rect(0, 0, width, height, plots[0]._theme.background)
    var cache = FontCache()
    var text_requests = _render_cells_generic(
        svg,
        width,
        height,
        plots,
        cells,
        row_weights,
        col_weights,
        shared_y_scale,
        align_axes,
        title,
        cache=cache,
    )
    _replay_text_requests_svg(svg, text_requests)
    return svg^


def save_grid(
    plots: List[Plot],
    cells: List[GridCell],
    width: Int,
    height: Int,
    path: String,
    row_weights: List[Float64] = List[Float64](),
    col_weights: List[Float64] = List[Float64](),
    shared_y_scale: Bool = False,
    align_axes: Bool = False,
    title: String = "",
) raises:
    """`render_grid()`'s counterpart that writes a file, picking the
    format from `plots[0]`'s theme or the path's extension.

    SVG output takes its accessible markup from `plots[0]`'s `.labels()`,
    the same best-effort rule `save_facets()` uses: the `<svg>` root
    needs exactly one title for a figure with many cells.

    Args:
        plots: The charts, one per cell.
        cells: Where each plot goes.
        width: Figure width.
        height: Figure height.
        path: Where to write.
        row_weights: Relative row heights, empty for equal rows.
        col_weights: Relative column widths, empty for equal columns.
        shared_y_scale: Give every cell one y-domain.
        align_axes: Share plot-rect edges, as `render_grid()`.
        title: A figure title above the cells, as `render_grid()`.

    Raises:
        Error: Whatever `render_grid()` raises, or a write failure.
    """
    _check_grid_args(plots, cells, "save_grid")
    var format = _resolve_output_format(plots[0]._theme.output_format, path)
    if format == OutputFormat.SVG:
        var f = open(path, "w")
        f.write(
            _svg_output_string(
                render_grid_svg(
                    plots,
                    cells,
                    width,
                    height,
                    row_weights,
                    col_weights,
                    shared_y_scale,
                    align_axes,
                    title,
                ),
                plots[0]._labels,
            )
        )
        f.close()
    elif format == OutputFormat.PNG:
        write_png(
            render_grid(
                plots,
                cells,
                width,
                height,
                row_weights,
                col_weights,
                shared_y_scale,
                align_axes,
                title,
            ),
            path,
        )
    else:
        write_bmp(
            render_grid(
                plots,
                cells,
                width,
                height,
                row_weights,
                col_weights,
                shared_y_scale,
                align_axes,
                title,
            ),
            path,
        )
