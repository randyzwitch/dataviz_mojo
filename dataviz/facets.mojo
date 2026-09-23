"""`render_facets()`: one plot per cell, laid out in a uniform grid.

The cell-layout work lives in `layout.mojo` and is shared with
`render_grid()`; a facet grid is that core's degenerate case, one cell
per plot with equal tracks. What is left here is the facet-shaped
interface to it: `cols` instead of a cell list, and a canvas size derived
from the plots rather than given.
"""

from canvas.bounds import BoundsTarget
from canvas.buffer import Canvas
from canvas.io.bmp import write_bmp
from canvas.io.png import write_png
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget
from canvas.vector.pdf import PdfCanvas, write_pdf
from canvas.vector.svg import SvgCanvas

from dataviz.layout import (
    Figure,
    _figure_title_band,
    _render_cells_generic,
    uniform_cells,
)
from dataviz.core.output_format import OutputFormat
from dataviz.plot import (
    Plot,
    _all_at_dpi,
    _ink_box,
    _resolve_output_format,
    _resolve_supersample,
    _svg_output_string,
)
from dataviz.core.text import (
    _TextRequest,
    _replay_text_requests,
)


def save_facets(
    plots: List[Plot],
    cols: Int,
    path: String,
    shared_y_scale: Bool = False,
    dpi: Float64 = 72.0,
    tight: Bool = False,
) raises:
    """`save()`'s `render_facets()`/`render_facets_svg()` counterpart; see
    `save_layers()` for the shared format/empty behavior.

    Each entry in `plots` is an independent `Plot` (its own data, labels,
    theme, mark), laid out into a grid of `cols` columns;
    `_require_uniform_size` requires every plot to have the same
    `.size()`. Build each cell's `Plot`, or use `scatter_facets()` to
    make panels from a DataFrame. `shared_y_scale` makes every cell share one y-domain
    (see `_render_facets_generic` for its `Mark.POINT`/`LINE`/
    `EFFECT_SCATTER`-only scope).

    `dpi` and `tight` mean what they do for `save()` (#701): `dpi` sets
    a raster export's pixels per inch, scaling every cell together so
    the grid keeps its proportions, and the vector formats ignore it;
    `tight` crops every format to the figure's ink.

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
    if cols <= 0:
        raise Error(
            "save_facets(): cols must be positive (got " + String(cols) + ")"
        )
    _require_uniform_size(plots, "save_facets")
    var format = _resolve_output_format(plots[0]._theme.output_format, path)
    if format == OutputFormat.SVG:
        var f = open(path, "w")
        if tight:
            var box = _facets_tight_box(plots, cols, shared_y_scale)
            var svg = SvgCanvas(box[2], box[3])
            svg.translate(-Float64(box[0]), -Float64(box[1]))
            _draw_facets_figure(svg, plots, cols, shared_y_scale, "", True)
            f.write(_svg_output_string(svg^, plots[0]._labels))
        else:
            f.write(
                _svg_output_string(
                    render_facets_svg(plots, cols, shared_y_scale),
                    plots[0]._labels,
                )
            )
        f.close()
    elif format == OutputFormat.PDF:
        if tight:
            var box = _facets_tight_box(plots, cols, shared_y_scale)
            var doc = PdfCanvas(box[2], box[3])
            doc.translate(-Float64(box[0]), -Float64(box[1]))
            _draw_facets_figure(doc, plots, cols, shared_y_scale, "", True)
            write_pdf(doc, path)
        else:
            var doc = render_facets_pdf(plots, cols, shared_y_scale)
            write_pdf(doc, path)
    else:
        var scaled = _all_at_dpi(plots, dpi, "save_facets")
        var canvas = _render_facets_tight(
            scaled, cols, shared_y_scale
        ) if tight else render_facets(scaled, cols, shared_y_scale)
        if format == OutputFormat.PNG:
            write_png(canvas, path)
        else:
            write_bmp(canvas, path)


def _facets_figure(
    plots: List[Plot],
    cols: Int,
    shared_y_scale: Bool = False,
    title: String = "",
) raises -> Figure:
    """A facet grid as an unrendered `Figure` (#697): one uniform cell
    per plot, `cols` across, sized as `render_facets()` sizes it, so
    rendering the figure draws what `render_facets()` draws."""
    if cols <= 0:
        raise Error(
            "render_facets(): cols must be positive (got " + String(cols) + ")"
        )
    _require_uniform_size(plots, "render_facets")
    var size = _facets_size(plots, cols, title)
    return Figure(
        plots.copy(),
        uniform_cells(len(plots), cols),
        size[0],
        size[1],
        shared_y_scale=shared_y_scale,
        title=title,
    )


def _facets_size(
    plots: List[Plot], cols: Int, title: String
) -> Tuple[Int, Int]:
    """A facet grid's figure size: `cols` cells across, as many rows as
    `plots` fills, each cell a plot's own size, plus the band a `title`
    reserves above them."""
    var rows = (len(plots) + cols - 1) // cols
    return (
        cols * plots[0].width,
        rows * plots[0].height + _figure_title_band(plots[0]._theme, title),
    )


def _draw_facets_figure[
    T: DrawTarget
](
    mut target: T,
    plots: List[Plot],
    cols: Int,
    shared_y_scale: Bool,
    title: String,
    fill_background: Bool,
) raises:
    """Draw a facet grid into `target` at its full size, background and
    text included -- what every facet export draws, measured or not
    (#701).

    Args:
        target: Where to draw; raster, vector or a measuring target.
        plots: The charts, one per cell.
        cols: Cells per row.
        shared_y_scale: Give every cell one y-domain.
        title: A figure title above the cells.
        fill_background: Whether to paint `plots[0]`'s background first;
            off while measuring, or the crop would be the whole page.

    Raises:
        Error: Whatever a cell's render raises.
    """
    var size = _facets_size(plots, cols, title)
    if fill_background:
        target.fill_rect(0, 0, size[0], size[1], plots[0]._theme.background)
    var cache = FontCache()
    var text_requests = _render_facets_generic(
        target,
        size[0],
        size[1],
        plots,
        cols,
        shared_y_scale,
        title,
        cache=cache,
        fill_cell_backgrounds=fill_background,
    )
    _replay_text_requests(target, text_requests, cache)


def _facets_tight_box(
    plots: List[Plot], cols: Int, shared_y_scale: Bool
) raises -> Tuple[Int, Int, Int, Int]:
    """`_tight_box` for a facet grid (#701): the box around its ink,
    measured by drawing it into a `BoundsTarget` without the background.
    """
    var size = _facets_size(plots, cols, "")
    var probe = BoundsTarget(size[0], size[1])
    _draw_facets_figure(probe, plots, cols, shared_y_scale, "", False)
    return _ink_box(probe, size[0], size[1])


def _render_facets_tight(
    plots: List[Plot], cols: Int, shared_y_scale: Bool
) raises -> Canvas:
    """`render_facets()` cropped to the figure's ink, laid out at full
    size and then cropped, as `render_tight()` does for one plot."""
    var box = _facets_tight_box(plots, cols, shared_y_scale)
    var factor = _resolve_supersample(plots[0], "save_facets")
    for i in range(1, len(plots)):
        var f = _resolve_supersample(plots[i], "save_facets")
        if f > factor:
            factor = f
    var canvas = Canvas(box[2], box[3], plots[0]._theme.background)
    canvas.begin_supersampled(factor, plots[0]._theme.background)
    canvas.translate(-Float64(box[0]), -Float64(box[1]))
    _draw_facets_figure(canvas, plots, cols, shared_y_scale, "", True)
    canvas.end_supersampled()
    return canvas^


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
    fill_cell_backgrounds: Bool = True,
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
        fill_cell_backgrounds=fill_cell_backgrounds,
    )
