"""Cell layout: the one core `render_facets()` and `render_grid()` share.

A figure made of cells is one idea with two faces. `render_facets()` is
the uniform one: `n` plots, `cols` per row, every cell the same size.
`render_grid()` is the unequal one: each plot names a row, a column
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

Insets are the other half of #347 and deliberately not cells.
`render_inset()` draws a base plot and then a second plot inside a
fractional sub-rect of the base's plot rect, over it. An inset is an
overlay, not a cell: it has no track, no weight and no neighbor, and
folding it into the grid model would distort both. It shares nothing
with the cell core beyond the two render helpers `render()` itself uses.
"""

from canvas.bounds import BoundsTarget
from canvas.buffer import Canvas
from canvas.io.bmp import write_bmp
from canvas.io.png import write_png
from canvas.text.font_cache import FontCache
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget
from canvas.vector.pdf import PdfCanvas, write_pdf
from canvas.vector.svg import SvgCanvas

from dataviz.core.annotations import (
    _draw_annotation_areas,
    _draw_annotation_bands,
    _draw_annotation_best_fit,
    _draw_annotation_smooth,
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
)
from dataviz.plot import Plot
from dataviz.rendering import (
    _all_at_dpi,
    _dpi_factor,
    _ink_box,
    _filled_annotations_go_under,
    _render_generic,
    _render_into,
    _render_svg_into,
    _resolve_output_format,
    _resolve_supersample,
    _svg_output_string,
)
from dataviz.core.extent import (
    _data_extent,
    _log_data_extent,
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
        var frame = _apply_labels(
            plots[i]._settings.labels,
            plots[i]._mark,
            plots[i]._settings.theme,
            cell_x0,
            cell_y0,
            cell_x1,
            cell_y1,
            cache=scratch_cache,
        )
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
    fill_cell_backgrounds: Bool = True,
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
        fill_cell_backgrounds: Paint each cell's background before its
            chart. Off only while a tight export measures the ink.

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
    var band = _figure_title_band(plots[0]._settings.theme, title)
    var x_edges = _weighted_edges(width, col_weights, cols)
    var y_edges = _weighted_edges(height - band, row_weights, rows)
    if band > 0:
        for k in range(len(y_edges)):
            y_edges[k] += band
        var theme = plots[0]._settings.theme
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
    var shared_y_is_log = shared_y_scale and plots[0]._settings.y_log
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
            if plots[i]._settings.labels.x_title.byte_length() > 0:
                any_x_title = True
            if plots[i]._settings.labels.title.byte_length() > 0:
                any_title = True
        wants_gutter = any_x_title and any_title
    var gutter = Int(
        _Scaled(plots[0]._settings.theme).label_gap * 2
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
        # including the strip a title's margin reserves -- except while
        # a tight export measures the ink, where a background covering
        # every cell would make the crop the whole figure (#701).
        if fill_cell_backgrounds:
            target.fill_rect(
                cell_x0,
                cell_y0,
                cell_x1 - cell_x0,
                cell_y1 - cell_y0,
                plots[i]._settings.theme.background,
            )
        var cell_content_y1 = cell_y1 - gutter
        # The inset rect the cell actually lays out in. Identical to the
        # cell rect unless align_axes asked for shared edges.
        var laid_x0 = cell_x0 + inset_left[i]
        var laid_x1 = cell_x1 - inset_right[i]
        var laid_y0 = cell_y0 + inset_top[i]
        var laid_y1 = cell_content_y1 - inset_bottom[i]
        var frame = _apply_labels(
            plots[i]._settings.labels,
            plots[i]._mark,
            plots[i]._settings.theme,
            laid_x0,
            laid_y0,
            laid_x1,
            laid_y1,
            cache=cache,
        )
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
            plots[i]._settings.labels,
            plots[i]._settings.theme,
            cell_x0,
            cell_y0,
            cell_x1,
            cell_content_y1,
            cell_result.px0,
            cell_result.py0,
            cell_result.px1,
            cell_result.py1,
            cache=cache,
        )
        # Each cell's annotations draw against that cell's own x/y scale,
        # in the same order a standalone render uses (areas and bands
        # underneath, then lines/vlines, points on top, best_fit last).
        var cell_under = _filled_annotations_go_under(plots[i]._mark)
        var cell_area_requests = List[
            _TextRequest
        ]() if cell_under else _draw_annotation_areas(
            target,
            plots[i]._annotations,
            cell_result,
            plots[i]._settings.theme,
            cache=cache,
        )
        var cell_band_requests = List[
            _TextRequest
        ]() if cell_under else _draw_annotation_bands(
            target,
            plots[i]._annotations,
            cell_result,
            plots[i]._settings.theme,
            cache=cache,
        )
        var cell_vline_requests = _draw_annotation_vlines(
            target,
            plots[i]._annotations,
            cell_result,
            plots[i]._settings.theme,
            cache=cache,
        )
        var cell_line_requests = _draw_annotation_lines(
            target,
            plots[i]._annotations,
            cell_result,
            plots[i]._settings.theme,
            cache=cache,
        )
        var cell_point_requests = _draw_annotation_points(
            target,
            plots[i]._annotations,
            cell_result,
            plots[i]._settings.theme,
            cache=cache,
        )
        _draw_annotation_smooth(
            target,
            plots[i]._annotations,
            plots[i]._continuous.x,
            plots[i]._continuous.y,
            cell_result,
            plots[i]._settings.theme,
        )
        var cell_best_fit_requests = _draw_annotation_best_fit(
            target,
            plots[i]._annotations,
            plots[i]._continuous.x,
            plots[i]._continuous.y,
            cell_result,
            plots[i]._settings.theme,
            cache=cache,
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


struct Figure(Copyable, Movable):
    """A composite chart -- several `Plot`s laid out in grid cells --
    that has not been rendered yet (#697).

    What `Plot` is for one chart: construction stores the layout and
    draws nothing, and the same value exports to any format through
    `render()`, `render_svg()`, `render_pdf()` or `save()`, exactly as
    a `Plot` does. `jointplot()`, `pairplot()` and `clustermap()`
    return one, so `save(pairplot(...), "pairs.svg")` works the way
    `save(scatter(x, y), "chart.svg")` does.

    It holds `render_grid()`'s arguments, and rendering one is
    `render_grid()` over them; a uniform facet grid is the case of one
    cell per plot with equal tracks, which is how `pairplot()` builds
    its figure.
    """

    var plots: List[Plot]
    """The charts, one per cell."""
    var cells: List[GridCell]
    """Where each plot goes."""
    var width: Int
    """Figure width, in points (1/72 inch), as `Plot.size()`."""
    var height: Int
    """Figure height, in points."""
    var row_weights: List[Float64]
    """Relative row heights, empty for equal rows."""
    var col_weights: List[Float64]
    """Relative column widths, empty for equal columns."""
    var shared_y_scale: Bool
    """Give every cell one y-domain."""
    var align_axes: Bool
    """Share plot-rect edges down each column and across each row."""
    var title: String
    """A figure title above the cells; empty for none."""

    def __init__(
        out self,
        var plots: List[Plot],
        var cells: List[GridCell],
        width: Int,
        height: Int,
        var row_weights: List[Float64] = List[Float64](),
        var col_weights: List[Float64] = List[Float64](),
        shared_y_scale: Bool = False,
        align_axes: Bool = False,
        title: String = "",
    ):
        """Store a layout; nothing is drawn or checked until it is
        rendered, as with `Plot`.

        Args:
            plots: The charts, one per cell.
            cells: Where each plot goes.
            width: Figure width in points.
            height: Figure height in points.
            row_weights: Relative row heights, empty for equal rows.
            col_weights: Relative column widths, empty for equal
                columns.
            shared_y_scale: Give every cell one y-domain.
            align_axes: Share plot-rect edges, as `render_grid()`.
            title: A figure title above the cells; empty for none.
        """
        self.plots = plots^
        self.cells = cells^
        self.width = width
        self.height = height
        self.row_weights = row_weights^
        self.col_weights = col_weights^
        self.shared_y_scale = shared_y_scale
        self.align_axes = align_axes
        self.title = title


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
    canvas.fill_rect(0, 0, width, height, plots[0]._settings.theme.background)
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
    svg.fill_rect(0, 0, width, height, plots[0]._settings.theme.background)
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
    _replay_text_requests(svg, text_requests, cache)
    return svg^


def render_grid_pdf(
    plots: List[Plot],
    cells: List[GridCell],
    width: Int,
    height: Int,
    row_weights: List[Float64] = List[Float64](),
    col_weights: List[Float64] = List[Float64](),
    shared_y_scale: Bool = False,
    align_axes: Bool = False,
    title: String = "",
) raises -> PdfCanvas:
    """`render_grid()`'s counterpart for a one-page `PdfCanvas` (#372),
    with the same cell layout. `width`/`height` are points, 1/72 inch,
    so the page is the figure.

    Args:
        plots: The charts, one per cell.
        cells: Where each plot goes.
        width: Figure width in points.
        height: Figure height in points.
        row_weights: Relative row heights, empty for equal rows.
        col_weights: Relative column widths, empty for equal columns.
        shared_y_scale: Give every cell one y-domain.
        align_axes: Share plot-rect edges, as `render_grid()`.
        title: A figure title above the cells, as `render_grid()`.

    Returns:
        The finished document.

    Raises:
        Error: As `render_grid()`.
    """
    _check_grid_args(plots, cells, "render_grid_pdf")
    var pdf = PdfCanvas(width, height)
    pdf.fill_rect(0, 0, width, height, plots[0]._settings.theme.background)
    var cache = FontCache()
    var text_requests = _render_cells_generic(
        pdf,
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
    _replay_text_requests(pdf, text_requests, cache)
    return pdf^


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
    dpi: Float64 = 72.0,
    tight: Bool = False,
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
        dpi: Pixels per inch for a raster export, as `save()`'s (#701):
            `width` and `height` are points, so 300 scales the figure,
            every cell's `Theme.scale` and the title band together. The
            vector formats ignore it.
        tight: Crop every format to the figure's ink, as `save()`'s.

    Raises:
        Error: Whatever `render_grid()` raises, or a write failure.
    """
    _check_grid_args(plots, cells, "save_grid")
    var format = _resolve_output_format(
        plots[0]._settings.theme.output_format, path
    )
    if format == OutputFormat.SVG:
        var f = open(path, "w")
        if tight:
            var box = _grid_tight_box(
                plots,
                cells,
                width,
                height,
                row_weights,
                col_weights,
                shared_y_scale,
                align_axes,
                title,
            )
            var svg = SvgCanvas(box[2], box[3])
            svg.translate(-Float64(box[0]), -Float64(box[1]))
            _draw_grid_figure(
                svg,
                plots,
                cells,
                width,
                height,
                row_weights,
                col_weights,
                shared_y_scale,
                align_axes,
                title,
                True,
            )
            f.write(_svg_output_string(svg^, plots[0]._settings.labels))
        else:
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
                    plots[0]._settings.labels,
                )
            )
        f.close()
    elif format == OutputFormat.PDF:
        if tight:
            var box = _grid_tight_box(
                plots,
                cells,
                width,
                height,
                row_weights,
                col_weights,
                shared_y_scale,
                align_axes,
                title,
            )
            var doc = PdfCanvas(box[2], box[3])
            doc.translate(-Float64(box[0]), -Float64(box[1]))
            _draw_grid_figure(
                doc,
                plots,
                cells,
                width,
                height,
                row_weights,
                col_weights,
                shared_y_scale,
                align_axes,
                title,
                True,
            )
            write_pdf(doc, path)
        else:
            var doc = render_grid_pdf(
                plots,
                cells,
                width,
                height,
                row_weights,
                col_weights,
                shared_y_scale,
                align_axes,
                title,
            )
            write_pdf(doc, path)
    else:
        var factor = _dpi_factor(dpi, "save_grid")
        var scaled = _all_at_dpi(plots, dpi, "save_grid")
        var w = Int(Float64(width) * factor + 0.5)
        var h = Int(Float64(height) * factor + 0.5)
        var canvas = _render_grid_tight(
            scaled,
            cells,
            w,
            h,
            row_weights,
            col_weights,
            shared_y_scale,
            align_axes,
            title,
        ) if tight else render_grid(
            scaled,
            cells,
            w,
            h,
            row_weights,
            col_weights,
            shared_y_scale,
            align_axes,
            title,
        )
        if format == OutputFormat.PNG:
            write_png(canvas, path)
        else:
            write_bmp(canvas, path)


def _draw_grid_figure[
    T: DrawTarget
](
    mut target: T,
    plots: List[Plot],
    cells: List[GridCell],
    width: Int,
    height: Int,
    row_weights: List[Float64],
    col_weights: List[Float64],
    shared_y_scale: Bool,
    align_axes: Bool,
    title: String,
    fill_background: Bool,
) raises:
    """Draw a grid figure into `target` at its full size, background and
    text included -- what every grid export draws, measured or not
    (#701). `fill_background` is off while measuring, or the crop would
    be the whole page.
    """
    if fill_background:
        target.fill_rect(
            0, 0, width, height, plots[0]._settings.theme.background
        )
    var cache = FontCache()
    var text_requests = _render_cells_generic(
        target,
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
        fill_cell_backgrounds=fill_background,
    )
    _replay_text_requests(target, text_requests, cache)


def _grid_tight_box(
    plots: List[Plot],
    cells: List[GridCell],
    width: Int,
    height: Int,
    row_weights: List[Float64],
    col_weights: List[Float64],
    shared_y_scale: Bool,
    align_axes: Bool,
    title: String,
) raises -> Tuple[Int, Int, Int, Int]:
    """`_tight_box` for a grid figure (#701): the box around its ink,
    measured by drawing it into a `BoundsTarget` without the background.
    """
    var probe = BoundsTarget(width, height)
    _draw_grid_figure(
        probe,
        plots,
        cells,
        width,
        height,
        row_weights,
        col_weights,
        shared_y_scale,
        align_axes,
        title,
        False,
    )
    return _ink_box(probe, width, height)


def _render_grid_tight(
    plots: List[Plot],
    cells: List[GridCell],
    width: Int,
    height: Int,
    row_weights: List[Float64],
    col_weights: List[Float64],
    shared_y_scale: Bool,
    align_axes: Bool,
    title: String,
) raises -> Canvas:
    """`render_grid()` cropped to the figure's ink, laid out at full size
    and then cropped, as `render_tight()` does for one plot."""
    var box = _grid_tight_box(
        plots,
        cells,
        width,
        height,
        row_weights,
        col_weights,
        shared_y_scale,
        align_axes,
        title,
    )
    var factor = _resolve_supersample(plots[0], "save_grid")
    for i in range(1, len(plots)):
        var f = _resolve_supersample(plots[i], "save_grid")
        if f > factor:
            factor = f
    var canvas = Canvas(box[2], box[3], plots[0]._settings.theme.background)
    canvas.begin_supersampled(factor, plots[0]._settings.theme.background)
    canvas.translate(-Float64(box[0]), -Float64(box[1]))
    _draw_grid_figure(
        canvas,
        plots,
        cells,
        width,
        height,
        row_weights,
        col_weights,
        shared_y_scale,
        align_axes,
        title,
        True,
    )
    canvas.end_supersampled()
    return canvas^


def _inset_rect(
    plot_rect: Tuple[Int, Int, Int, Int],
    x: Float64,
    y: Float64,
    width: Float64,
    height: Float64,
    caller: String,
) raises -> Tuple[Int, Int, Int, Int]:
    """The inset's pixel rect from its fractions of the base's plot rect.

    The fractions are checked here rather than at the top of the caller
    so the raster and vector entry points cannot drift on what they
    accept. Each edge is rounded from the fraction rather than from an
    accumulated width, so an inset at `x + width == 1.0` ends exactly on
    the plot rect's right edge.

    Args:
        plot_rect: The base's `(px0, py0, px1, py1)`.
        x: Left edge, as a fraction of the plot rect's width from its
            left.
        y: Top edge, as a fraction of the plot rect's height from its
            top.
        width: Width as a fraction of the plot rect's width.
        height: Height as a fraction of the plot rect's height.
        caller: The entry point to name in an error.

    Returns:
        `(x0, y0, x1, y1)` in pixels.

    Raises:
        Error: A fraction outside `[0, 1]`, a non-positive size, an
            inset that runs past the plot rect, or one that rounds to
            nothing.
    """
    if x < 0.0 or x > 1.0:
        raise Error(caller + "(): x must be within [0, 1] -- got " + String(x))
    if y < 0.0 or y > 1.0:
        raise Error(caller + "(): y must be within [0, 1] -- got " + String(y))
    if width <= 0.0:
        raise Error(
            caller + "(): width must be positive -- got " + String(width)
        )
    if height <= 0.0:
        raise Error(
            caller + "(): height must be positive -- got " + String(height)
        )
    if x + width > 1.0:
        raise Error(
            caller
            + "(): the inset runs past the plot rect's right edge -- x + width"
            " is "
            + String(x + width)
        )
    if y + height > 1.0:
        raise Error(
            caller
            + "(): the inset runs past the plot rect's bottom edge -- y +"
            " height is "
            + String(y + height)
        )
    var pw = Float64(plot_rect[2] - plot_rect[0])
    var ph = Float64(plot_rect[3] - plot_rect[1])
    var x0 = plot_rect[0] + Int(x * pw + 0.5)
    var y0 = plot_rect[1] + Int(y * ph + 0.5)
    var x1 = plot_rect[0] + Int((x + width) * pw + 0.5)
    var y1 = plot_rect[1] + Int((y + height) * ph + 0.5)
    if x1 - x0 < 1 or y1 - y0 < 1:
        raise Error(
            caller
            + "(): the inset rounds to nothing -- "
            + String(x1 - x0)
            + " by "
            + String(y1 - y0)
            + " pixels of a "
            + String(Int(pw))
            + " by "
            + String(Int(ph))
            + " plot rect"
        )
    return (x0, y0, x1, y1)


def _inset_outer_bounds(
    inset: Plot, rect: Tuple[Int, Int, Int, Int], width: Int, height: Int
) raises -> Tuple[Int, Int, Int, Int]:
    """The outer bounds that put `inset`'s plot rect on `rect`.

    A plot's plot rect is its outer bounds less the margins its own tick
    labels, axis titles and title need, and those margins come from
    measured text, so the only way to know them is to render once and
    ask. Same approach as `align_axes`: one scratch render into a raster
    the figure's size, read where the plot rect landed, and expand the
    bounds by the difference. Margins depend on the rect's size and
    content, not on where it starts, so the expansion holds.

    Args:
        inset: The plot being placed.
        rect: Where its plot rect should land, `(x0, y0, x1, y1)`.
        width: The figure's width, for the scratch canvas.
        height: The figure's height.

    Returns:
        `(x0, y0, x1, y1)` to hand `_render_into`, each edge pushed out
        by that side's margin; it may extend past the figure, where the
        labels are simply clipped.

    Raises:
        Error: Whatever rendering `inset` raises.
    """
    var scratch = Canvas(width, height, inset._settings.theme.background)
    var landed = _render_into(
        scratch, inset, rect[0], rect[1], rect[2], rect[3]
    )
    return (
        rect[0] - (landed[0] - rect[0]),
        rect[1] - (landed[1] - rect[1]),
        rect[2] + (rect[2] - landed[2]),
        rect[3] + (rect[3] - landed[3]),
    )


def render_inset(
    base: Plot,
    inset: Plot,
    x: Float64,
    y: Float64,
    width: Float64,
    height: Float64,
) raises -> Canvas:
    """Render `base` as `render()` would, then `inset` over it inside a
    sub-rect of the base's plot rect: a zoomed detail inside the chart it
    details (#347).

    The four fractions are of the base's *plot rect*, the area inside its
    margins and axes where the marks are, not of the canvas, and they
    describe the inset's own plot rect, its axes area. `x` and `y` place that area's top-left corner from the base plot
    rect's top-left, in the row-down order every grid in this library
    reads, so `x=0.55, y=0.05, width=0.4, height=0.4` is the top-right
    quarter. Only that area is painted with the inset's background, so
    it covers the base beneath it; the inset's tick labels, axis titles
    and title sit outside it, over the base, rather than on a blank panel
    that would punch a larger hole than the axes. The inset draws its own legend and annotations,
    and its own `.size()` is ignored, as a cell's is in `render_grid()`.

    The canvas is the base's size, supersampled by the larger of the two
    plots' factors so a curved inset over a bar chart is drawn at the
    curve's factor.

    ```mojo
    from dataviz import Plot, render_inset
    from canvas.io.png import write_png

    def main():
        var x = List[Float64](0.0, 1.0, 2.0, 3.0, 4.0, 5.0)
        var y = List[Float64](1.0, 4.0, 2.0, 5.0, 3.0, 6.0)
        var base = Plot().mark_line().encode(x=x, y=y).size(640, 420)
        var detail = Plot().mark_point().encode(
            x=List[Float64](2.0, 3.0), y=List[Float64](2.0, 5.0)
        )
        write_png(render_inset(base, detail, 0.55, 0.05, 0.4, 0.4), "inset.png")
    ```

    Args:
        base: The chart drawn first, at its own size.
        inset: The chart drawn over it.
        x: The inset's left edge, as a fraction of the base's plot-rect
            width from the plot rect's left.
        y: The inset's top edge, as a fraction of the plot-rect height
            from the plot rect's top.
        width: The inset's width as a fraction of the plot-rect width.
        height: The inset's height as a fraction of the plot-rect height.

    Returns:
        The rendered figure, `base.width` by `base.height`.

    Raises:
        Error: A fraction outside `[0, 1]`, a non-positive size, an
            inset that runs past the plot rect or rounds to nothing, or
            anything rendering either plot raises.
    """
    var factor = _resolve_supersample(base, "render_inset")
    var inset_factor = _resolve_supersample(inset, "render_inset")
    if inset_factor > factor:
        factor = inset_factor
    var canvas = Canvas(
        base.width, base.height, base._settings.theme.background
    )
    canvas.begin_supersampled(factor, base._settings.theme.background)
    var plot_rect = _render_into(canvas, base, 0, 0, base.width, base.height)
    var r = _inset_rect(plot_rect, x, y, width, height, "render_inset")
    var outer = _inset_outer_bounds(inset, r, base.width, base.height)
    canvas.fill_rect(
        r[0], r[1], r[2] - r[0], r[3] - r[1], inset._settings.theme.background
    )
    _ = _render_into(
        canvas,
        inset,
        outer[0],
        outer[1],
        outer[2],
        outer[3],
        fill_background=False,
    )
    canvas.end_supersampled()
    return canvas^


def render_inset_svg(
    base: Plot,
    inset: Plot,
    x: Float64,
    y: Float64,
    width: Float64,
    height: Float64,
) raises -> SvgCanvas:
    """`render_inset()`'s counterpart for `SvgCanvas`: the same placement
    rule against the base's plot rect, through `render_svg()`'s own
    helper.

    Args:
        base: The chart drawn first, at its own size.
        inset: The chart drawn over it.
        x: The inset's left edge, as a fraction of the plot-rect width.
        y: The inset's top edge, as a fraction of the plot-rect height.
        width: The inset's width as a fraction of the plot-rect width.
        height: The inset's height as a fraction of the plot-rect height.

    Returns:
        The rendered figure.

    Raises:
        Error: As `render_inset()`.
    """
    var svg = SvgCanvas(base.width, base.height)
    var plot_rect = _render_svg_into(svg, base, 0, 0, base.width, base.height)
    var r = _inset_rect(plot_rect, x, y, width, height, "render_inset_svg")
    var outer = _inset_outer_bounds(inset, r, base.width, base.height)
    svg.fill_rect(
        r[0], r[1], r[2] - r[0], r[3] - r[1], inset._settings.theme.background
    )
    _ = _render_svg_into(
        svg,
        inset,
        outer[0],
        outer[1],
        outer[2],
        outer[3],
        fill_background=False,
    )
    return svg^
