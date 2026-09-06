"""`render_facets()`: one plot per cell, laid out in a grid.

Split out of `plot.mojo` (#222). Each cell is an independent render
into a sub-rect of one shared canvas, which is why this is so much
smaller than `layers.mojo`: facets do not have to reconcile anything
between cells unless `shared_y_scale` asks them to.
"""

from canvas.buffer import Canvas
from canvas.io.bmp import write_bmp
from canvas.io.png import write_png
from canvas.resize import downsample
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget
from canvas.vector.svg import SvgCanvas

from dataviz.annotations import (
    _draw_annotation_areas,
    _draw_annotation_bands,
    _draw_annotation_best_fit,
    _draw_annotation_lines,
    _draw_annotation_points,
    _draw_annotation_vlines,
)
from dataviz.layers import render_layers, render_layers_svg, save_layers
from dataviz.mark import Mark
from dataviz.output_format import OutputFormat
from dataviz.plot import (
    Plot,
    _data_extent,
    _log_data_extent,
    _render_generic,
    _render_into,
    _require_positive_supersample,
    _resolve_output_format,
    _svg_output_string,
    render,
    save,
    write_accessible_svg,
)
from dataviz.text import (
    _TextRequest,
    _apply_labels,
    _extend_text_requests,
    _label_text_requests,
    _replay_text_requests,
    _replay_text_requests_svg,
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

    SVG output writes accessible markup automatically (#212) from
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
    plots: List[Plot], cols: Int, shared_y_scale: Bool = False
) raises -> Canvas:
    """Render each of `plots` into its grid cell of a fresh `Canvas` sized
    from the plots (`_require_uniform_size`), supersampled by
    `plots[0]._theme.raster_supersample` like `render()` (`plots` is a
    plain borrow, #208 -- a copy is what actually gets the scale bump,
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
    var factor = plots[0]._theme.raster_supersample
    _require_positive_supersample(factor, "render_facets")
    var canvas = Canvas(
        cols * plots[0].width * factor, rows * plots[0].height * factor
    )
    # The half-pixel that box-downsampling costs: downsample() averages
    # the device block f*p .. f*p+f-1 into output pixel p, whose centre
    # sits at user coordinate p + (f-1)/(2f). Scaling alone therefore
    # lands everything (f-1)/(2f) px early -- 0.25 at factor 2, 0.333 at
    # 3, 0.375 at 4 -- so the origin shifts by (f-1)/2 device px first.
    canvas.translate(Float64(factor - 1) / 2.0, Float64(factor - 1) / 2.0)
    canvas.scale(Float64(factor), Float64(factor))
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    # Logical figure bounds, not the scratch canvas's: the transform maps
    # user space up to the supersampled device space.
    var text_requests = _render_facets_generic(
        canvas,
        cols * plots[0].width,
        rows * plots[0].height,
        plots,
        cols,
        shared_y_scale,
        cache=cache,
    )
    _replay_text_requests(canvas, text_requests, cache)
    return downsample(canvas, factor)


def render_facets_svg(
    plots: List[Plot], cols: Int, shared_y_scale: Bool = False
) raises -> SvgCanvas:
    """`render_facets()`'s counterpart for `SvgCanvas`, with the same `cols`
    guard and `_render_facets_generic` core.
    """
    if cols <= 0:
        raise Error(
            "render_facets_svg(): cols must be positive (got "
            + String(cols)
            + ")"
        )
    _require_uniform_size(plots, "render_facets_svg")
    var rows = (len(plots) + cols - 1) // cols
    var svg = SvgCanvas(cols * plots[0].width, rows * plots[0].height)
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    var text_requests = _render_facets_generic(
        svg, svg.width, svg.height, plots, cols, shared_y_scale, cache=cache
    )
    _replay_text_requests_svg(svg, text_requests)
    return svg^


def _render_facets_generic[
    T: DrawTarget
](
    mut target: T,
    width: Int,
    height: Int,
    plots: List[Plot],
    cols: Int,
    shared_y_scale: Bool = False,
    *,
    mut cache: FontCache,
) raises -> List[_TextRequest]:
    """The shared cell-layout core `render_facets()`/`render_facets_svg()`
    delegate to. `width`/`height` are passed in because `DrawTarget` has
    no size accessor.

    `cols` columns, enough rows to fit `len(plots)`; a partial final row
    leaves cells blank. Each cell is laid out as a standalone render
    would lay out the whole target, with its own `Plot.labels()` titles
    and every `annotate_*()` kind (areas, bands, lines, vlines, points,
    best_fit), by pointing `_render_generic`'s bounds at the cell's
    label-shrunk rect. Cell boundaries are `width * col // cols`, so
    adjacent cells share the exact boundary pixel.

    `shared_y_scale` gives every cell one y-domain (`_data_extent` over
    the union of every cell's `y_data`, or `_log_data_extent` when every
    cell agrees on `Plot.scale_y_log()` -- #217). Only `Mark.POINT`/
    `LINE`/`EFFECT_SCATTER` support it, every cell must use one of those
    marks, and it doesn't combine with `y_err*` (the shared union isn't
    widened for whiskers); `_render_generic` raises for each case,
    including a log/linear mix.
    """
    var text_requests = List[_TextRequest]()
    if cols <= 0:
        raise Error(
            "render_facets(): cols must be positive (got " + String(cols) + ")"
        )
    if len(plots) == 0:
        return text_requests^

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
            for v in plots[i].y_data:
                combined_y.append(v)
        var domain = _log_data_extent(
            combined_y
        ) if shared_y_is_log else _data_extent(combined_y)
        shared_y_min = domain.domain_min
        shared_y_max = domain.domain_max

    var rows = (len(plots) + cols - 1) // cols
    for i in range(len(plots)):
        var row = i // cols
        var col = i % cols
        var cell_x0 = width * col // cols
        var cell_x1 = width * (col + 1) // cols
        var cell_y0 = height * row // rows
        var cell_y1 = height * (row + 1) // rows
        # Each cell's full rect is filled with that cell's background,
        # including the strip a title's margin reserves.
        target.fill_rect(
            cell_x0,
            cell_y0,
            cell_x1 - cell_x0,
            cell_y1 - cell_y0,
            plots[i]._theme.background,
        )
        var frame = _apply_labels(plots[i], cell_x0, cell_y0, cell_x1, cell_y1)
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
            cell_y1,
            cell_result.px0,
            cell_result.py0,
            cell_result.px1,
            cell_result.py1,
        )
        # Each cell's annotations draw against that cell's own x/y scale, in
        # the same order a standalone render uses (areas and bands
        # underneath, then lines/vlines, points on top, best_fit last).
        # cell_result comes straight from _render_generic, so a continuous
        # mark's cell carries a real x_scale/y_scale and a categorical
        # mark's cell correctly has has_x_scale=False -- each pass below
        # raises its own "no continuous axis" error exactly as it would for
        # a standalone plot, with no extra branching needed here.
        var cell_area_requests = _draw_annotation_areas(
            target, plots[i], cell_result, plots[i]._theme
        )
        var cell_band_requests = _draw_annotation_bands(
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
