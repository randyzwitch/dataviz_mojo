"""`render_facets()`: one plot per cell, laid out in a uniform grid.

The cell-layout work lives in `layout.mojo` and is shared with
`render_grid()`; a facet grid is that core's degenerate case, one cell
per plot with equal tracks. What is left here is the facet-shaped
interface to it: `cols` instead of a cell list, and a canvas size derived
from the plots rather than given.
"""

from canvas.buffer import Canvas
from canvas.io.bmp import write_bmp
from canvas.io.png import write_png
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget
from canvas.vector.pdf import PdfCanvas, write_pdf
from canvas.vector.svg import SvgCanvas

from dataviz.layout import (
    _figure_title_band,
    _render_cells_generic,
    uniform_cells,
)
from dataviz.core.output_format import OutputFormat
from dataviz.plot import (
    Plot,
    _resolve_output_format,
    _resolve_supersample,
    _svg_output_string,
)
from dataviz.core.text import (
    _TextRequest,
    _replay_text_requests,
)


def save_facets(
    plots: List[Plot], cols: Int, path: String, shared_y_scale: Bool = False
) raises:
    """`save()`'s `render_facets()`/`render_facets_svg()` counterpart; see
    `save_layers()` for the shared format/empty behavior.

    Each entry in `plots` is an independent `Plot` (its own data, labels,
    theme, mark), laid out into a grid of `cols` columns;
    `_require_uniform_size` requires every plot to have the same
    `.size()`. There is no `facet_by()`; build each cell's `Plot` and
    pass the list. `shared_y_scale` makes every cell share one y-domain
    (see `_render_facets_generic` for its `Mark.POINT`/`LINE`/
    `EFFECT_SCATTER`-only scope).

    See the Cookbook's "Facets" and "Shared Facet Scale" recipes
    (docs/cookbook_recipes/).

    SVG output writes accessible markup automatically from
    `plots[0]`'s `.labels()`, as a best-effort document title for the
    whole grid -- each cell can carry its own visible title, but the
    `<svg>` root needs exactly one `aria-label`/`<title>`. Give `plots[0]`
    a title that describes the grid as a whole (or call
    `write_accessible_svg()` directly) when that matters.
    """
    if len(plots) == 0:
        raise Error("save_facets(): plots must not be empty")
    var format = _resolve_output_format(plots[0]._theme.output_format, path)
    if format == OutputFormat.SVG:
        var f = open(path, "w")
        f.write(
            _svg_output_string(
                render_facets_svg(plots, cols, shared_y_scale), plots[0]._labels
            )
        )
        f.close()
    elif format == OutputFormat.PDF:
        var doc = render_facets_pdf(plots, cols, shared_y_scale)
        write_pdf(doc, path)
    elif format == OutputFormat.PNG:
        write_png(render_facets(plots, cols, shared_y_scale), path)
    else:
        write_bmp(render_facets(plots, cols, shared_y_scale), path)


def _require_uniform_size(plots: List[Plot], caller: String) raises:
    """`render_facets()`/`render_facets_svg()`/`render_layers()`/
    `render_layers_svg()`'s shared precondition: every `Plot` in `plots`
    must have the same `.size()`, since the grid/shared canvas is derived
    from the plots. Raises naming `caller` on a mismatch or an empty
    list.
    """
    if len(plots) == 0:
        raise Error(caller + "(): plots must not be empty")
    var width = plots[0].width
    var height = plots[0].height
    for i in range(1, len(plots)):
        if plots[i].width != width or plots[i].height != height:
            raise Error(
                caller
                + "(): every Plot must share the same .size() -- plots[0] is "
                + String(width)
                + "x"
                + String(height)
                + ", plots["
                + String(i)
                + "] is "
                + String(plots[i].width)
                + "x"
                + String(plots[i].height)
            )


def render_facets(
    plots: List[Plot],
    cols: Int,
    shared_y_scale: Bool = False,
    title: String = "",
) raises -> Canvas:
    """Render each of `plots` into its grid cell of a fresh `Canvas` sized
    from the plots (`_require_uniform_size`), plus the band a `title`
    reserves above them so the cells keep their own size, supersampled by
    `plots[0]._theme.raster_supersample` like `render()` (`plots` is a
    plain borrow -- a copy is what actually gets the scale bump,
    so a temporary list literal binds fine). See `_render_facets_generic`
    for the cell-layout contract. `cols` is checked before anything
    else, since a non-positive value would divide by zero in the
    `rows`/canvas-size math.
    """
    if cols <= 0:
        raise Error(
            "render_facets(): cols must be positive (got " + String(cols) + ")"
        )
    _require_uniform_size(plots, "render_facets")
    var rows = (len(plots) + cols - 1) // cols
    # One canvas, so one factor must serve every plot on it: take the
    # largest any of them asks for rather than the first plot's, or a
    # curved mark beside a bar chart would be drawn at the bar's factor.
    var factor = _resolve_supersample(plots[0], "render_facets")
    for i in range(1, len(plots)):
        var f = _resolve_supersample(plots[i], "render_facets")
        if f > factor:
            factor = f
    var figure_height = rows * plots[0].height + _figure_title_band(
        plots[0]._theme, title
    )
    var canvas = Canvas(cols * plots[0].width, figure_height)
    # `begin_supersampled` owns the half-pixel shift box downsampling
    # costs and the scale, and replays the recorded shapes one output
    # band at a time, so the enlarged buffer never exists whole. Byte
    # identical to the two-step recipe it replaces (canvas_mojo#391).
    canvas.begin_supersampled(factor)
    # A plot count that is not a multiple of `cols` leaves squares in the
    # last row with no cell in them. Each cell fills its own rect, so
    # those were filled by nobody and came out white: invisible on the
    # default light theme and a hole in the corner of any other (#568).
    # Filled before the cells so each cell's own fill still wins, and
    # entirely overdrawn when the last row is full.
    canvas.fill_rect(
        0,
        0,
        cols * plots[0].width,
        figure_height,
        plots[0]._theme.background,
    )
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    # Logical figure bounds, not the scratch canvas's: the transform maps
    # user space up to the supersampled device space.
    var text_requests = _render_facets_generic(
        canvas,
        cols * plots[0].width,
        figure_height,
        plots,
        cols,
        shared_y_scale,
        title,
        cache=cache,
    )
    _replay_text_requests(canvas, text_requests, cache)
    canvas.end_supersampled()
    return canvas^


def render_facets_svg(
    plots: List[Plot],
    cols: Int,
    shared_y_scale: Bool = False,
    title: String = "",
) raises -> SvgCanvas:
    """`render_facets()`'s counterpart for `SvgCanvas`, with the same `cols`
    guard, title band and `_render_facets_generic` core.
    """
    if cols <= 0:
        raise Error(
            "render_facets_svg(): cols must be positive (got "
            + String(cols)
            + ")"
        )
    _require_uniform_size(plots, "render_facets_svg")
    var rows = (len(plots) + cols - 1) // cols
    var svg = SvgCanvas(
        cols * plots[0].width,
        rows * plots[0].height + _figure_title_band(plots[0]._theme, title),
    )
    # See render_facets(): a partial last row is a hole without this.
    svg.fill_rect(0, 0, svg.width, svg.height, plots[0]._theme.background)
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    var text_requests = _render_facets_generic(
        svg,
        svg.width,
        svg.height,
        plots,
        cols,
        shared_y_scale,
        title,
        cache=cache,
    )
    _replay_text_requests(svg, text_requests, cache)
    return svg^


def render_facets_pdf(
    plots: List[Plot],
    cols: Int,
    shared_y_scale: Bool = False,
    title: String = "",
) raises -> PdfCanvas:
    """`render_facets()`'s counterpart for a one-page `PdfCanvas`, with
    the same `cols` guard, title band and `_render_facets_generic` core
    (#372). The figure's size is in points, 1/72 inch, so the page is
    the figure.

    Args:
        plots: The charts, one per cell.
        cols: Cells per row.
        shared_y_scale: Give every cell one y-domain.
        title: A figure title above the cells.

    Returns:
        The finished document.

    Raises:
        Error: As `render_facets()`.
    """
    if cols <= 0:
        raise Error(
            "render_facets_pdf(): cols must be positive (got "
            + String(cols)
            + ")"
        )
    _require_uniform_size(plots, "render_facets_pdf")
    var rows = (len(plots) + cols - 1) // cols
    var pdf = PdfCanvas(
        cols * plots[0].width,
        rows * plots[0].height + _figure_title_band(plots[0]._theme, title),
    )
    pdf.fill_rect(0, 0, pdf.width, pdf.height, plots[0]._theme.background)
    var cache = FontCache()
    var text_requests = _render_facets_generic(
        pdf,
        pdf.width,
        pdf.height,
        plots,
        cols,
        shared_y_scale,
        title,
        cache=cache,
    )
    _replay_text_requests(pdf, text_requests, cache)
    return pdf^


def _render_facets_generic[
    T: DrawTarget
](
    mut target: T,
    width: Int,
    height: Int,
    plots: List[Plot],
    cols: Int,
    shared_y_scale: Bool = False,
    title: String = "",
    *,
    mut cache: FontCache,
) raises -> List[_TextRequest]:
    """A uniform grid, expressed as cells and handed to
    `_render_cells_generic()`. `width`/`height` are passed in because
    `DrawTarget` has no size accessor.

    `cols` columns, enough rows to fit `len(plots)`; a partial final row
    leaves cells blank. Everything a cell does -- its own labels, its own
    legend, all six `annotate_*()` passes, the gutter between stacked
    rows, and `shared_y_scale` -- is the shared core's, so a facet grid
    and a gridspec figure cannot drift apart.

    `shared_y_scale` gives every cell one y-domain. Only
    `Mark.POINT`/`LINE`/`AREA`/`EFFECT_SCATTER` support it, every cell
    must use one of those marks, and it does not combine with `y_err*`
    (the shared union is not widened for whiskers); `_render_generic`
    raises for each case, including a log/linear mix.
    """
    if cols <= 0:
        raise Error(
            "render_facets(): cols must be positive (got " + String(cols) + ")"
        )
    var text_requests = List[_TextRequest]()
    if len(plots) == 0:
        return text_requests^
    return _render_cells_generic(
        target,
        width,
        height,
        plots,
        uniform_cells(len(plots), cols),
        List[Float64](),
        List[Float64](),
        shared_y_scale,
        title=title,
        cache=cache,
    )
