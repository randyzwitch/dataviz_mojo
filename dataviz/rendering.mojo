"""The rendering pipeline and every output entry point: `render()`,
`render_svg()`, `render_pdf()`, the `render_tight*()` variants,
`save()` and the accessible-SVG writers, plus the `[T: DrawTarget]`
core they share (`_render_generic`, `_draw_figure_into`) and the
supersample, dpi and output-format resolution around it.

Split out of plot.mojo, which imports from here what its methods use;
see plot.mojo's header for the circular-import convention this
follows."""

from dataviz.core.chart_settings import _ChartSettings
from canvas.bounds import BoundsTarget
from canvas.buffer import Canvas
from canvas.io.bmp import write_bmp
from canvas.io.png import write_png
from canvas.vector.draw_target import DrawTarget
from canvas.vector.pdf import PdfCanvas, write_pdf
from canvas.vector.svg import SvgCanvas
from canvas.text.font_cache import FontCache
from dataviz.basic.continuous import (
    _draw_area_layer,
    _draw_line_layer,
    _draw_point_layer,
)
from dataviz.core.point_channels import _PointChannels
from dataviz.layout import (
    Figure,
    render_grid,
    render_grid_pdf,
    render_grid_svg,
    save_grid,
)
from dataviz.core.frame import _draw_continuous_axis_frame
from dataviz.core.legend import (
    _legend_origin_x,
    _legend_origin_y,
    _legend_reserve_for,
)
from dataviz.core.text import (
    _Scaled,
    _TextRequest,
    _apply_labels,
    _extend_text_requests,
    _label_text_requests,
    _replay_text_requests,
)
from dataviz.core.validate import (
    _check_missing_policy,
    _check_unsupported_flags,
    _domain_override_scale,
    _require_non_empty,
    _validate_color_domain,
    _validate_continuous_encoding,
    _validate_domain_override,
    _validate_tick_override,
)
from dataviz.core.axis_controls import _AxisControls
from dataviz.core.annotations import (
    _draw_annotation_areas,
    _draw_annotation_arrows,
    _draw_annotation_bands,
    _draw_annotation_best_fit,
    _draw_annotation_lines,
    _draw_annotation_points,
    _draw_annotation_smooth,
    _draw_annotation_vlines,
    _validate_log_scale_annotations,
    _AnnotationData,
)
from dataviz.core.mark import Feature, Mark, _supporting_names
from dataviz.core.output_format import OutputFormat
from dataviz.core.render_result import _RenderResult
from dataviz.core.scale import LinearScale
from dataviz.core.theme import Theme
from dataviz.binned.histogram import _draw_histogram_layer, _HistogramData
from dataviz.chart import AnyChart, ChartLike
from dataviz.core.plot_fields import (
    _LabelData,
    _ChannelData,
    _ContinuousData,
    _ErrorBarData,
    _MarkStyle,
)
from dataviz.core.extent import (
    _data_extent,
    _log_data_extent,
    _symlog_data_extent,
    _zero_baseline_y_extent,
)


def _require_positive_supersample(factor: Int, context: String) raises:
    """Raise unless `factor >= 1`, naming the caller (`context`). Guards
    `Theme.raster_supersample` at each of its three read sites
    (`render()`/`render_facets()`/`render_layers()`) rather than in
    `Theme`'s own constructor, matching `line_smoothing`'s deferred-to-
    render-time validation (`_check_line_smoothing`, elsewhere in this
    file) -- a `Theme` value isn't wrong to construct, only to render
    with.
    """
    if factor < 1:
        raise Error(
            context
            + "(): Theme.raster_supersample must be >= 1 (got "
            + String(factor)
            + ")"
        )


comptime _AUTO_SUPERSAMPLE = 0
"""`Theme.raster_supersample`'s "let the mark decide" value, and its
default. An explicit 1 or more always wins; this only picks a factor
for a caller who has not expressed one.
"""


comptime _CURVED_SUPERSAMPLE = 3
"""Supersample factor for circles, arcs, and curved strokes."""


def _auto_supersample(mark: Mark, theme: Theme) -> Int:
    """Return the mark-specific supersample factor for `AUTO`."""
    # A smoothed line or area is a curve whatever its mark says, so it
    # is classified by what it draws rather than by its name.
    if theme.line_smoothing > 0.0:
        return _CURVED_SUPERSAMPLE

    var m = mark
    if (
        m == Mark.BAR
        or m == Mark.GROUPED_BAR
        or m == Mark.STACKED_BAR
        or m == Mark.WATERFALL
        or m == Mark.BULLET
        or m == Mark.GANTT
        or m == Mark.SPAN_CHART
        or m == Mark.BOX
        or m == Mark.CANDLESTICK
        or m == Mark.HEATMAP
        or m == Mark.IMSHOW
        or m == Mark.PCOLORMESH
        or m == Mark.HIST2D
        or m == Mark.MARIMEKKO
        or m == Mark.TREEMAP
        or m == Mark.SANKEY
        or m == Mark.LINE
        or m == Mark.AREA
        or m == Mark.HISTOGRAM
        or m == Mark.VIOLIN
        or m == Mark.PARALLEL
        or m == Mark.RADAR
        or m == Mark.TRICONTOUR
    ):
        return 1
    return _CURVED_SUPERSAMPLE


def _resolve_supersample(
    mark: Mark, theme: Theme, context: String
) raises -> Int:
    """`Theme.raster_supersample` if the caller set one, else the mark's
    own factor. Validated here so every entry point gets the same check.

    Args:
        mark: The mark being rendered.
        theme: Its theme.
        context: The caller's name, for the error message.

    Returns:
        The factor to supersample by.

    Raises:
        Error: The theme's factor is negative.
    """
    var configured = theme.raster_supersample
    if configured == _AUTO_SUPERSAMPLE:
        return _auto_supersample(mark, theme)
    _require_positive_supersample(configured, context)
    return configured


def render[C: ChartLike](plot: C) raises -> Canvas:
    """Render `plot` into a fresh `Canvas` sized `plot.canvas_width()` x `plot.canvas_height()`
    and return it, supersampled by `plot._settings.theme.raster_supersample`
    (default automatic, resolved per mark by `_auto_supersample()`):
    the drawing is recorded once at logical coordinates and replayed
    into the canvas one output band at a time, each band rendered at
    that many times the size and averaged down. The enlarged buffer
    never exists whole.

    Supersampling uses the canvas transform; `Theme.scale` independently
    controls layout density.

    `plot` is a plain borrow: copying instead of mutating in
    place means `render(scatter(x, y))` and `save(scatter(x, y), path)`
    both compile inline, with no need to bind a temporary to a variable
    first.
    """
    var factor = _resolve_supersample(
        plot.id(), plot.chart_settings().theme, "render"
    )
    var out = Canvas(
        plot.canvas_width(),
        plot.canvas_height(),
        plot.chart_settings().theme.background,
    )
    # `begin_supersampled` owns the half-pixel shift box downsampling
    # costs and the scale, and replays the recorded shapes one output
    # band at a time, so the enlarged buffer never exists whole. Byte
    # identical to the two-step recipe it replaces (canvas_mojo#391).
    #
    # Every mark takes this path. A bulk marker call used to force the
    # region to materialize, so a plain scatter was faster on the old
    # two-step recipe and `render()` chose per plot; canvas_mojo v0.33.3
    # records the whole call as one op and that was the last primitive
    # that did so (benchmarks/METHODOLOGY.md).
    out.begin_supersampled(factor, plot.chart_settings().theme.background)
    _ = _render_into(out, plot, 0, 0, plot.canvas_width(), plot.canvas_height())
    out.end_supersampled()
    return out^


struct _DrawnFigure(Movable):
    """What `_draw_figure_into` drew: the inner plot rect, and every
    label the pass collected, already in replay order.

    The labels are handed back rather than drawn so that they go on
    after every mark and annotation pass, on top; the caller hands
    them to `_replay_text_requests`. What the struct buys is that the
    *drawing* -- the background, the labels' margins, the mark, and
    the seven annotation passes -- is written once instead of once per
    backend.
    """

    var px0: Int
    var py0: Int
    var px1: Int
    var py1: Int
    var text: List[_TextRequest]

    def __init__(
        out self,
        px0: Int,
        py0: Int,
        px1: Int,
        py1: Int,
        var text: List[_TextRequest],
    ):
        self.px0 = px0
        self.py0 = py0
        self.px1 = px1
        self.py1 = py1
        self.text = text^


def _draw_figure_into[
    C: ChartLike, T: DrawTarget
](
    mut target: T,
    plot: C,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    fill_background: Bool,
    vector_target: Bool,
    mut cache: FontCache,
) raises -> _DrawnFigure:
    """Draw everything of `plot` except its text into `target`, and
    return the inner plot rect with the labels the pass collected.

    The shared body of `_render_into`, `_render_svg_into` and
    `_render_pdf_into`, which were three near-identical copies differing
    only in the target's type and `vector_target`. Every piece they
    called was already generic over `T: DrawTarget`, and since #578 so
    is the replay.

    It is also what lets a figure be *measured* rather than drawn:
    `_tight_box` runs this into a `BoundsTarget`, which keeps the union
    of what it was asked to draw and paints nothing (#372). A fourth
    copy of sixty lines would have been the alternative, and copies of
    this particular body have drifted before.

    Args:
        target: Where to draw.
        plot: The chart.
        ox0: Outer left bound.
        oy0: Outer top bound.
        ox1: Outer right bound.
        oy1: Outer bottom bound.
        fill_background: Whether to fill the outer rect first;
            `render_inset()` passes False so its labels sit over the
            base rather than on a blank panel.
        vector_target: Passed to `_render_generic`, which draws some
            marks differently when the output is markup rather than
            pixels.
        cache: The render's shared font cache.

    Returns:
        The inner plot rect and the collected labels.

    Raises:
        Error: Whatever the mark's render raises.
    """
    var settings = plot.chart_settings()
    var annotations = plot.chart_annotations()
    var mark = plot.id()
    if fill_background:
        target.fill_rect(
            ox0, oy0, ox1 - ox0, oy1 - oy0, settings.theme.background
        )
    var frame = _apply_labels(
        plot.chart_settings().labels,
        mark,
        settings.theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    var result = plot.render_mark(
        target,
        frame.ox0,
        frame.oy0,
        frame.ox1,
        frame.oy1,
        False,
        0.0,
        0.0,
        False,
        cache=cache,
        vector_target=vector_target,
    )
    var text = _label_text_requests(
        plot.chart_settings().labels,
        settings.theme,
        ox0,
        oy0,
        ox1,
        oy1,
        result.px0,
        result.py0,
        result.px1,
        result.py1,
        cache=cache,
    )
    var under_mark = _filled_annotations_go_under(mark)
    if not under_mark:
        _extend_text_requests(
            text,
            _draw_annotation_areas(
                target,
                annotations,
                result,
                settings.theme,
                cache=cache,
            ),
        )
        _extend_text_requests(
            text,
            _draw_annotation_bands(
                target,
                annotations,
                result,
                settings.theme,
                cache=cache,
            ),
        )
    _extend_text_requests(
        text,
        _draw_annotation_vlines(
            target, annotations, result, settings.theme, cache=cache
        ),
    )
    _extend_text_requests(
        text,
        _draw_annotation_lines(
            target, annotations, result, settings.theme, cache=cache
        ),
    )
    _extend_text_requests(
        text,
        _draw_annotation_points(
            target, annotations, result, settings.theme, cache=cache
        ),
    )
    _extend_text_requests(
        text,
        _draw_annotation_arrows(
            target, annotations, result, settings.theme, cache=cache
        ),
    )
    _draw_annotation_smooth(
        target,
        annotations,
        plot.x_data(),
        plot.y_data(),
        result,
        settings.theme,
    )
    _extend_text_requests(
        text,
        _draw_annotation_best_fit(
            target,
            annotations,
            plot.x_data(),
            plot.y_data(),
            result,
            settings.theme,
            cache=cache,
        ),
    )
    _extend_text_requests(text, result.text_requests)
    return _DrawnFigure(result.px0, result.py0, result.px1, result.py1, text^)


def render_tight[C: ChartLike](plot: C) raises -> Canvas:
    """`render()` cropped to the figure's ink: the whitespace a fixed
    figure size reserves for a longer title or a legend that is not
    there is trimmed away (#372).

    The figure is laid out at its full `size()` and then cropped, rather
    than being laid out smaller -- laying out smaller would change where
    everything goes, and the crop would chase a moving target instead of
    framing the figure the caller asked for.

    The ink is measured with `_tight_box`, which draws the figure into a
    `BoundsTarget` that paints nothing and keeps the union of the
    extents. Text counts: a title's box is the box of the glyphs the
    same layout would draw.

    A figure with no ink keeps its full size, since a zero-sized canvas
    is not usable.

    Args:
        plot: The chart to render.

    Returns:
        A canvas the size of the figure's ink.

    Raises:
        Error: Whatever `render()` raises.
    """
    var box = _tight_box(plot, False)
    var factor = _resolve_supersample(
        plot.id(), plot.chart_settings().theme, "render_tight"
    )
    var out = Canvas(box[2], box[3], plot.chart_settings().theme.background)
    out.begin_supersampled(factor, plot.chart_settings().theme.background)
    # Draw the figure at its full size into a smaller canvas, shifted so
    # the ink's top-left lands at the origin. Everything outside the
    # canvas is clipped, which is exactly the crop.
    out.translate(-Float64(box[0]), -Float64(box[1]))
    _ = _render_into(out, plot, 0, 0, plot.canvas_width(), plot.canvas_height())
    out.end_supersampled()
    return out^


def render_tight_svg[C: ChartLike](plot: C) raises -> SvgCanvas:
    """`render_svg()` cropped to the figure's ink; `render_tight()`'s
    vector counterpart (#372).

    The same three steps -- measure, size, redraw -- and the reason the
    measuring target was worth asking canvas for: an `SvgCanvas` has no
    pixels to scan for ink, so nothing else could have answered this.

    Args:
        plot: The chart to render.

    Returns:
        An `SvgCanvas` the size of the figure's ink.

    Raises:
        Error: Whatever `render_svg()` raises.
    """
    var box = _tight_box(plot, True)
    var svg = SvgCanvas(box[2], box[3])
    svg.translate(-Float64(box[0]), -Float64(box[1]))
    _ = _render_svg_into(
        svg, plot, 0, 0, plot.canvas_width(), plot.canvas_height()
    )
    return svg^


def render_tight_pdf[C: ChartLike](plot: C) raises -> PdfCanvas:
    """`render_pdf()` cropped to the figure's ink, so the page is the
    figure rather than the figure plus its margins (#372).

    The page shrinks with the crop, and one layout unit is still one
    point, so a cropped export is still physically specified -- it is
    simply a smaller page.

    Args:
        plot: The chart to render.

    Returns:
        A one-page `PdfCanvas` the size of the figure's ink.

    Raises:
        Error: Whatever `render_pdf()` raises.
    """
    var box = _tight_box(plot, True)
    var pdf = PdfCanvas(box[2], box[3])
    pdf.translate(-Float64(box[0]), -Float64(box[1]))
    _ = _render_pdf_into(
        pdf, plot, 0, 0, plot.canvas_width(), plot.canvas_height()
    )
    return pdf^


def _tight_box[
    C: ChartLike
](plot: C, vector_target: Bool) raises -> Tuple[Int, Int, Int, Int]:
    """The whole-pixel box around everything `plot` would draw, as
    `(x, y, width, height)` in the figure's own coordinates (#372).

    Measured by drawing the figure into a `BoundsTarget`, which keeps
    the union of the extents it is asked to draw and paints nothing.
    That is the only way to get this for a vector backend: a raster
    canvas could be scanned for non-background pixels, but an
    `SvgCanvas` or a `PdfCanvas` has no pixels to scan, and a figure
    that cropped only for PNG would be the wrong shape for a feature
    whose point is publication output.

    The background fill is deliberately skipped while measuring. It
    covers the whole page by construction, so counting it would make
    every box the full page and the crop a no-op.

    A figure with no ink at all -- no marks, no labels -- keeps its
    full size rather than collapsing to nothing, since a zero-sized
    canvas is not a thing a caller can use.

    Args:
        plot: The chart to measure.
        vector_target: Whether the real draw will be to a vector
            backend; passed through so the measured geometry is the
            geometry that will be drawn.

    Returns:
        `(x, y, width, height)`.

    Raises:
        Error: Whatever the mark's render raises.
    """
    var probe = BoundsTarget(plot.canvas_width(), plot.canvas_height())
    var cache = FontCache()
    var drawn = _draw_figure_into(
        probe,
        plot,
        0,
        0,
        plot.canvas_width(),
        plot.canvas_height(),
        False,
        vector_target,
        cache,
    )
    _replay_text_requests(probe, drawn.text, cache)
    return _ink_box(probe, plot.canvas_width(), plot.canvas_height())


def _render_into[
    C: ChartLike
](
    mut canvas: Canvas,
    plot: C,
    ox0: Int = 0,
    oy0: Int = 0,
    ox1: Int = -1,
    oy1: Int = -1,
    fill_background: Bool = True,
) raises -> Tuple[Int, Int, Int, Int]:
    """Render `plot` into `canvas` within the outer bounds (background, then
    the axis frame and mark, then annotations and text). `ox1`/`oy1`
    default to -1, meaning the canvas's width/height; every current
    caller renders into the whole canvas, but the bounds stay generic
    since `_render_generic` is.

    Fills the whole original rect with `theme.background` (the only
    background fill on this path; the mark-specific renders fill
    nothing), reserves title margins via `_apply_labels`, hands the
    shrunk rect to `_render_generic`, builds the title requests via
    `_label_text_requests` from the inner rect it returned, runs the
    annotation passes, then draws every `_TextRequest` via
    `canvas.text.draw_text`.

    Scales only by `plot._settings.theme.scale` as given; `render()` applies
    `Theme.raster_supersample` by bumping that value on a copy before
    this call. Hand-verified pixel tests go through `render()` and so see
    supersampled output, exact for any solid-color interior point.

    `fill_background=False` skips the outer fill, for `render_inset()`,
    which paints only the inset's plot rect so its labels sit over the
    base rather than on a blank panel.

    Returns:
        The inner plot rect as `(px0, py0, px1, py1)`, the area the mark
        was drawn in after margins and labels; `render_inset()` places an
        inset against it.
    """
    var cx1 = ox1 if ox1 >= 0 else canvas.width
    var cy1 = oy1 if oy1 >= 0 else canvas.height
    # One FontCache for the whole render, built on first use: every
    # measurement the layout makes (tick labels, legend entries) and
    # then every label drawn afterwards resolve fonts and rasterize
    # glyphs through it once.
    var cache = FontCache()
    var drawn = _draw_figure_into(
        canvas, plot, ox0, oy0, cx1, cy1, fill_background, False, cache
    )
    _replay_text_requests(canvas, drawn.text, cache)
    return (drawn.px0, drawn.py0, drawn.px1, drawn.py1)


def render_svg[C: ChartLike](plot: C) raises -> SvgCanvas:
    """Render `plot` into a fresh `SvgCanvas` sized `plot.canvas_width()` x
    `plot.canvas_height()` and return it; `render()`'s vector counterpart,
    wrapping `_render_svg_into`.
    """
    var svg = SvgCanvas(plot.canvas_width(), plot.canvas_height())
    _ = _render_svg_into(svg, plot)
    return svg^


def _render_svg_into[
    C: ChartLike
](
    mut svg: SvgCanvas,
    plot: C,
    ox0: Int = 0,
    oy0: Int = 0,
    ox1: Int = -1,
    oy1: Int = -1,
    fill_background: Bool = True,
) raises -> Tuple[Int, Int, Int, Int]:
    """`_render_into`'s counterpart for `SvgCanvas`: same bounds resolution,
    `_apply_labels`/`_render_generic` core, and annotation passes, with
    the `_TextRequest`s drawn via `SvgCanvas.draw_text`. `render_svg()`
    is its only caller.

    `fill_background=False` skips the outer fill, for `render_inset()`,
    which paints only the inset's plot rect so its labels sit over the
    base rather than on a blank panel.

    Returns:
        The inner plot rect as `(px0, py0, px1, py1)`, the area the mark
        was drawn in after margins and labels; `render_inset()` places an
        inset against it.
    """
    var cx1 = ox1 if ox1 >= 0 else svg.width
    var cy1 = oy1 if oy1 >= 0 else svg.height
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    var drawn = _draw_figure_into(
        svg, plot, ox0, oy0, cx1, cy1, fill_background, True, cache
    )
    _replay_text_requests(svg, drawn.text, cache)
    return (drawn.px0, drawn.py0, drawn.px1, drawn.py1)


def _path_extension(path: String) -> String:
    """`path`'s extension, lowercased and including its dot, or an empty
    string when the last path component hasn't got one.

    Only the last component is considered, so a dot in a directory name
    (`charts.v2/out`) is not an extension. A leading dot is a hidden
    file rather than an extension, so `.gitignore` has none.
    """
    var lower = path.lower()
    var name = lower
    var slash = lower.rfind("/")
    if slash >= 0:
        name = String(lower[byte = slash + 1 :])
    var dot = name.rfind(".")
    if dot <= 0:
        return String("")
    return String(name[byte=dot:])


def _resolve_output_format(
    theme_format: OutputFormat, path: String
) raises -> OutputFormat:
    """The format `save()`/`save_layers()`/`save_facets()` use: `path`'s
    extension when it's `.svg`/`.png`/`.bmp`/`.pdf` (case-insensitive),
    or `theme_format` (`Theme.output_format`) when `path` has no
    extension at all.

    **Any other extension raises** (#755). This used to fall through to
    `theme_format` like an absent one, so `save(plot, "chart.jpg")`
    wrote SVG markup into a file named `.jpg` and reported success --
    the same defect #696 fixed for the already-rendered canvases, still
    the default here for every extension nobody had thought of. `.jpg`,
    `.jpeg`, `.gif`, `.webp`, `.tif` and `.html` all did it.

    An allow-list rather than a list of known-wrong extensions, because
    the set of formats this package can write is closed and small while
    the set it cannot is not.

    Args:
        theme_format: The fallback for a path with no extension.
        path: The destination.

    Returns:
        The format to write.

    Raises:
        Error: `path` has an extension this package cannot write.
    """
    var ext = _path_extension(path)
    if ext == ".svg":
        return OutputFormat.SVG
    elif ext == ".png":
        return OutputFormat.PNG
    elif ext == ".bmp":
        return OutputFormat.BMP
    elif ext == ".pdf":
        return OutputFormat.PDF
    elif ext.byte_length() == 0:
        return theme_format
    raise Error(
        "save(): don't know how to write a "
        + ext
        + " file. This package writes .svg, .png, .bmp and .pdf; a path"
        + " with no extension at all uses Theme.output_format. Nothing"
        + " was written to "
        + path
        + "."
    )


def _resolve_description(labels: _LabelData) -> String:
    """`labels.description`, or `labels.subtitle` when that's empty
    -- the `<desc>` `_svg_output_string()` passes to
    `accessible_svg_string()`, so a title-and-subtitle chart gets a
    reasonable screen-reader description with no extra call needed.
    """
    return (
        labels.description if labels.description.byte_length()
        > 0 else labels.subtitle
    )


def _svg_output_string(var svg: SvgCanvas, labels: _LabelData) raises -> String:
    """What `save()`/`save_layers()`/`save_facets()` write for SVG output
    : `accessible_svg_string()`'s markup when `labels.title` is set
        (`_resolve_description()`'s `<desc>`), or plain `svg.to_string()`
        otherwise. A pure string decision, factored out of the file-writing
        `save*()` functions so it's directly testable with no disk I/O.

    Takes the canvas by value, for the reason `accessible_svg_string()`
    does; every caller here passes a freshly rendered one.
    """
    if labels.title.byte_length() > 0:
        return accessible_svg_string(
            svg^, labels.title, _resolve_description(labels)
        )
    return svg.to_string()


def render_pdf[C: ChartLike](plot: C) raises -> PdfCanvas:
    """Render `plot` into a one-page `PdfCanvas` sized `plot.canvas_width()` by
    `plot.canvas_height()` points and return it; `render_svg()`'s counterpart for
    a print-ready document (#372).

    **One layout unit is one PDF point, 1/72 inch**, which is the whole
    physical-size contract: a 640 by 420 chart is a 640 by 420 point
    page, 8.89 by 5.83 inches. `size_inches()`/`size_mm()` say it the
    other way round. Nothing is resampled on the way out, because
    nothing is a pixel: paths stay paths and text stays text, embedded
    as a font subset so a label is selectable and searchable rather
    than a picture of itself.

    **What an export promises is the same glyphs, not the same bytes**
    (#631). The subset embedded here is cut from whichever copy of the
    family the machine has, and two packagings of one family -- DejaVu
    from `apt` and from `brew`, say -- agree on every outline while
    differing in the hinting programs they carry. So the same chart
    exported on two machines draws identically and compares
    byte-for-byte unequal, and a build that diffs or caches PDFs should
    compare the rendering rather than the file.

    Byte-identity would mean shipping a font rather than resolving one,
    which is a packaging decision and not one this contract makes. The
    font is most of a small document -- a two-word label embeds roughly
    12 KB of a 14 KB file -- so a byte comparison is mostly a
    comparison of the machine's font anyway.

    A family the machine does not have raises rather than substituting
    silently, so a wrong font is never quietly embedded.

    `Theme.scale` still multiplies every font size, margin and stroke
    width as it does on the other backends, so it changes how large the
    furniture is *on the page* rather than how many pixels it gets. The
    raster supersample factor has no meaning here and is ignored.

    Args:
        plot: The chart to render.

    Returns:
        The finished document, ready for `canvas.vector.pdf.write_pdf`
        or the `save()` path that wraps it.

    Raises:
        Error: Whatever rendering the plot raises.
    """
    var pdf = PdfCanvas(plot.canvas_width(), plot.canvas_height())
    _ = _render_pdf_into(
        pdf, plot, 0, 0, plot.canvas_width(), plot.canvas_height()
    )
    return pdf^


def _render_pdf_into[
    C: ChartLike
](
    mut pdf: PdfCanvas,
    plot: C,
    ox0: Int = 0,
    oy0: Int = 0,
    ox1: Int = -1,
    oy1: Int = -1,
    fill_background: Bool = True,
) raises -> Tuple[Int, Int, Int, Int]:
    """`_render_svg_into`'s counterpart for `PdfCanvas`: same bounds
    resolution, `_apply_labels`/`_render_generic` core and annotation
    passes, with the `_TextRequest`s drawn through
    `_replay_text_requests`.

    Args:
        pdf: The document to draw into.
        plot: The chart.
        ox0: Left edge of the bounds to lay out in.
        oy0: Top edge.
        ox1: Right edge; -1 means the page width.
        oy1: Bottom edge; -1 means the page height.
        fill_background: Whether to paint the theme's background over
            the bounds first.

    Returns:
        The inner plot rect as `(px0, py0, px1, py1)`.

    Raises:
        Error: Whatever rendering the plot raises.
    """
    var cx1 = ox1 if ox1 >= 0 else pdf.width
    var cy1 = oy1 if oy1 >= 0 else pdf.height
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    var drawn = _draw_figure_into(
        pdf, plot, ox0, oy0, cx1, cy1, fill_background, True, cache
    )
    _replay_text_requests(pdf, drawn.text, cache)
    return (drawn.px0, drawn.py0, drawn.px1, drawn.py1)


def _at_dpi[
    C: ChartLike
](plot: C, dpi: Float64, caller: String = "save") raises -> C:
    """`plot` laid out for a raster export at `dpi` (#372).

    The figure's size is in points, 1/72 inch, so a raster at `dpi`
    wants `dpi / 72` pixels per point. Multiplying the target's size
    alone would spread the same furniture over more pixels and print
    the text at a third of its physical size; multiplying `Theme.scale`
    by the same factor keeps every font size, margin and stroke width
    the same fraction of the page. So the output is the same figure at
    a finer resolution, which is what asking for a resolution means.

    Args:
        plot: The chart, sized in points.
        dpi: Pixels per inch for the export.
        caller: The public function to name in the error.

    Returns:
        A copy sized and scaled for that resolution; `plot` itself at
        72, where the factor is 1.

    Raises:
        Error: `dpi` is not positive.
    """
    if dpi <= 0.0:
        raise Error(
            caller + "(): dpi must be positive (got " + String(dpi) + ")"
        )
    var factor = dpi / 72.0
    if factor == 1.0:
        return plot.copy()
    return plot.scaled_by(factor)


def _all_at_dpi(
    plots: List[AnyChart], dpi: Float64, caller: String
) raises -> List[AnyChart]:
    """`_at_dpi` over every plot of a composition (#701).

    Every plot gets the same factor, so a layered chart's layers, a
    facet grid's cells and a grid's cells all keep their proportions to
    each other as well as to the page. The composition's own geometry --
    a figure title band, the gap under it -- comes from `plots[0]`'s
    `Theme` through `_Scaled`, so it scales with them.

    Args:
        plots: The composition's charts.
        dpi: Pixels per inch for the export.
        caller: The public function to name in the error.

    Returns:
        A scaled copy of each.

    Raises:
        Error: `dpi` is not positive.
    """
    var out = List[AnyChart](capacity=len(plots))
    for p in plots:
        out.append(_at_dpi(p, dpi, caller))
    return out^


def _dpi_factor(dpi: Float64, caller: String) raises -> Float64:
    """`dpi / 72`, the pixels per point `_at_dpi` scales a figure by,
    validated the same way -- for a figure whose size is given in the
    call rather than read from its plots (`save_grid()`)."""
    if dpi <= 0.0:
        raise Error(
            caller + "(): dpi must be positive (got " + String(dpi) + ")"
        )
    return dpi / 72.0


def _ink_box(
    probe: BoundsTarget, width: Int, height: Int
) -> Tuple[Int, Int, Int, Int]:
    """What `probe` measured, as `(x, y, width, height)`: the figure's
    full `width` by `height` when nothing was drawn, since a zero-sized
    canvas is not usable. The tail of `_tight_box`, shared with the
    compositions' tight exports (#701)."""
    if not probe.has_ink():
        return (0, 0, width, height)
    return probe.ink_pixels()


def save[
    C: ChartLike
](plot: C, path: String, dpi: Float64 = 72.0, tight: Bool = False) raises:
    """Render `plot` and write it to `path` in one call. The format
    comes from the path's extension -- `.svg`, `.png`, `.bmp` or `.pdf`
    -- or from `plot.chart_settings().theme.output_format` when `path` has no extension
    at all; `PNG`/`BMP` both go through `render()` and differ only in
    the writer.

    **Any other extension raises and writes nothing** (#755). A `.jpg`
    path used to fall back to the theme format like an absent one, so
    it got SVG markup in a file named `.jpg` and the call reported
    success.

    `plot` is a plain borrow: `save(scatter(x, y), path)` compiles
    inline, with no need to bind the temporary to a variable first. Call
    `render()`/`render_svg()` directly to get the `Canvas`/`SvgCanvas`
    itself. `save_layers()`/`save_facets()` are the `List[AnyChart]`
    counterparts; the `save(canvas: Canvas, path)` overload below writes
    an already-rendered `Canvas`.

    `tight=True` crops the output to the figure's ink, trimming the
    whitespace a fixed `size()` reserves for a longer title or an
    absent legend (#372). It applies to every format, because the
    measurement is taken from the drawing rather than from pixels; see
    `render_tight()`.

    `dpi` applies to the raster formats and says how many pixels one
    inch of the figure gets. The figure's own size is in points, 1/72
    inch (`Plot.size()`), so the default of 72 is one pixel per point
    and every existing call renders exactly as before; 300 gives the
    same figure at print resolution, with the text and strokes the same
    fraction of the page rather than a third the size. The vector
    formats ignore it, having no pixels to count. A `.pdf` path writes a
    one-page document through `render_pdf()`.

    SVG output with a non-empty `.labels(title=...)` writes accessible
    markup automatically, via `_svg_output_string()`/
    `accessible_svg_string()` with that title and `_resolve_description()`'s
    `<desc>` -- the same markup `write_accessible_svg()` adds explicitly,
    for callers who don't need a title that differs from the visible one.
    An untitled plot's SVG is unaffected.
    """
    var format = _resolve_output_format(
        plot.chart_settings().theme.output_format, path
    )
    # Each arm binds its canvas with `^` rather than through a ternary:
    # none of the three canvas types is `ImplicitlyCopyable`, so a
    # ternary would have to copy one to choose between the branches.
    if format == OutputFormat.SVG:
        var f = open(path, "w")
        if tight:
            var vector = render_tight_svg(plot)
            f.write(_svg_output_string(vector^, plot.chart_settings().labels))
        else:
            var vector = render_svg(plot)
            f.write(_svg_output_string(vector^, plot.chart_settings().labels))
        f.close()
    elif format == OutputFormat.PDF:
        if tight:
            var doc = render_tight_pdf(plot)
            write_pdf(doc, path)
        else:
            var doc = render_pdf(plot)
            write_pdf(doc, path)
    elif format == OutputFormat.PNG:
        var scaled = _at_dpi(plot, dpi)
        if tight:
            write_png(render_tight(scaled), path)
        else:
            write_png(render(scaled), path)
    else:
        var bmp_scaled = _at_dpi(plot, dpi)
        if tight:
            write_bmp(render_tight(bmp_scaled), path)
        else:
            write_bmp(render(bmp_scaled), path)


def _require_extension(
    path: String,
    because: String,
    accepted: String,
    allowed: List[String],
) raises:
    """Raise before opening `path` unless its extension is one this
    canvas can produce (#696, #755).

    Before #696, `save(canvas, "chart.pdf")` wrote PNG bytes and
    `save(svg, "chart.pdf")` wrote markup. That fix listed the
    extensions each overload had to refuse, which left every extension
    nobody had thought of still falling through to the default writer:
    `save(canvas, "chart.jpg")` wrote a PNG. A file that says `.jpg`
    and holds a PNG is worse than a failed save, because nothing
    reports it.

    So the test is now the other way round. The set of formats a given
    canvas can write is closed and has one or two members; the set it
    cannot is every other string. An absent extension is still allowed
    through to the caller's chosen writer, which is what lets
    `save(canvas, "out")` work.

    Checked before the file is opened, so a rejected path is left
    untouched rather than created and truncated.

    `because` is the canvas's own explanation, kept per-canvas rather
    than generated, so a caller gets the same sentence that told them
    something useful before this was centralized.

    Args:
        path: The destination.
        because: Why this canvas cannot write that format.
        accepted: The extension this canvas writes, for the message.
        allowed: The extensions it can write.

    Raises:
        Error: `path` has an extension outside `allowed`.
    """
    var ext = _path_extension(path)
    if ext.byte_length() == 0:
        return
    for ok in allowed:
        if ext == ok:
            return
    raise Error(
        "save(): cannot write a "
        + ext
        + " file here -- "
        + because
        + " Save it as "
        + accepted
        + ", or build the chart as a Plot and call"
        + " save(plot, path), which renders whatever format the"
        + " extension asks for."
    )


def render(figure: Figure) raises -> Canvas:
    """Render a composite `Figure` to a raster `Canvas`; `render(plot)`'s
    counterpart, over `render_grid()` (#697).

    Args:
        figure: The composite chart.

    Returns:
        The rendered figure.

    Raises:
        Error: Whatever `render_grid()` raises for its layout.
    """
    return render_grid(
        figure.plots,
        figure.cells,
        figure.width,
        figure.height,
        figure.row_weights,
        figure.col_weights,
        figure.shared_y_scale,
        figure.align_axes,
        figure.title,
    )


def render_svg(figure: Figure) raises -> SvgCanvas:
    """Render a composite `Figure` to vector markup; `render_svg(plot)`'s
    counterpart, over `render_grid_svg()` (#697).

    Args:
        figure: The composite chart.

    Returns:
        The rendered figure.

    Raises:
        Error: Whatever `render_grid_svg()` raises for its layout.
    """
    return render_grid_svg(
        figure.plots,
        figure.cells,
        figure.width,
        figure.height,
        figure.row_weights,
        figure.col_weights,
        figure.shared_y_scale,
        figure.align_axes,
        figure.title,
    )


def render_pdf(figure: Figure) raises -> PdfCanvas:
    """Render a composite `Figure` to a one-page PDF; `render_pdf(plot)`'s
    counterpart, over `render_grid_pdf()` (#697).

    Args:
        figure: The composite chart.

    Returns:
        The finished document.

    Raises:
        Error: Whatever `render_grid_pdf()` raises for its layout.
    """
    return render_grid_pdf(
        figure.plots,
        figure.cells,
        figure.width,
        figure.height,
        figure.row_weights,
        figure.col_weights,
        figure.shared_y_scale,
        figure.align_axes,
        figure.title,
    )


def save(
    figure: Figure, path: String, dpi: Float64 = 72.0, tight: Bool = False
) raises:
    """Render a composite `Figure` and write it to `path`; `save(plot)`'s
    counterpart (#697), with the same format rule and the same `dpi`
    and `tight` (see `save_grid()`, which this delegates to).

    Args:
        figure: The composite chart.
        path: Where to write; the extension picks the format.
        dpi: Pixels per inch for a raster export; ignored by vector.
        tight: Crop every format to the figure's ink.

    Raises:
        Error: Whatever `save_grid()` raises.
    """
    save_grid(
        figure.plots,
        figure.cells,
        figure.width,
        figure.height,
        path,
        figure.row_weights,
        figure.col_weights,
        figure.shared_y_scale,
        figure.align_axes,
        figure.title,
        dpi=dpi,
        tight=tight,
    )


def save(svg: SvgCanvas, path: String) raises:
    """Write an already-rendered `SvgCanvas` to `path` (#620).

    The vector counterpart of the `Canvas` overload below, so a document
    already rendered through `render_svg()` -- a `Plot`'s or a
    `Figure`'s -- is saved the same way every other chart is rather
    than reaching for canvas's own writer. A raster extension
    raises: this is markup, and turning it into pixels is `render()`'s
    job from the `Plot` it came from, at whatever size and resolution
    that caller wants.

    Args:
        svg: The rendered document.
        path: Where to write it; the extension must be `.svg`, or
            absent.

    Raises:
        Error: A `.png` or `.bmp` path, or the write fails.
    """
    var allowed: List[String] = [".svg"]
    _require_extension(
        path,
        "an SvgCanvas is vector markup, not pixels.",
        ".svg",
        allowed,
    )
    var f = open(path, "w")
    f.write(svg.to_string())
    f.close()


def save(canvas: Canvas, path: String) raises:
    """Write an already-rendered `Canvas` to `path`: BMP for a `.bmp`
    extension, PNG otherwise. A `.svg` path raises, since raster pixels
    can't become vector markup.
    """
    var allowed: List[String] = [".png", ".bmp"]
    _require_extension(
        path,
        "a Canvas is already-rendered raster pixels.",
        ".png or .bmp",
        allowed,
    )
    if path.lower().endswith(".bmp"):
        write_bmp(canvas, path)
    else:
        write_png(canvas, path)


def save(var pdf: PdfCanvas, path: String) raises:
    """Write an already-rendered `PdfCanvas` to `path` (#696).

    The third rendered-canvas overload, completing the set: before it,
    a caller holding a `PdfCanvas` had no `save()` at all and had to
    reach for `canvas.vector.pdf.write_pdf` while every other canvas
    type saved through this function.

    Takes the document by value rather than by `mut`, so
    `save(render_pdf(plot), path)` compiles inline the way
    `save(scatter(x, y), path)` does; `write_pdf` needs a mutable
    document because writing finalizes it, and an owned parameter is
    mutable without forcing the caller to bind a temporary first.

    Args:
        pdf: The rendered document.
        path: Where to write it; the extension must be `.pdf`, or
            absent.

    Raises:
        Error: A `.png`, `.bmp` or `.svg` path, or the write fails.
    """
    var allowed: List[String] = [".pdf"]
    _require_extension(
        path,
        "a PdfCanvas is a finished PDF document.",
        ".pdf",
        allowed,
    )
    write_pdf(pdf, path)


def accessible_svg_string(
    var svg: SvgCanvas, title: String, description: String = ""
) raises -> String:
    """`svg.to_string()` with SVG accessibility markup added: `role="img"`
    and `aria-label` on the root `<svg>` element, plus a `<title>` (and a
    `<desc>` when `description` is non-empty) as its first child
    elements, which is what screen readers that support SVG look for.

    `title` is required; the same string passed to `.labels(title=...)`
    is usually right.

    `SvgCanvas.set_title()` does the work. This was once a
    post-processing wrapper that spliced the attributes and children into
    `to_string()`'s output as text, which meant depending on `<svg ...>`
    being the literal start of that output and on two of canvas_mojo's
    private escaping helpers. Nothing upstream owed us either (#572).

    This only helps where the SVG's accessible tree is walked: inline
    `<svg>` markup, a standalone `.svg`, or an `<object>`/`<iframe>`
    embed. A plain `<img src="chart.svg">` (how the docs site embeds
    examples) treats the SVG as an opaque image, and a screen reader
    reads the `<img>`'s `alt` text instead.

    Taking the canvas by value is the one visible change: `set_title()`
    is a mutation and `SvgCanvas` is movable but not copyable, so a
    caller holding one passes `svg^` rather than `svg`. Every call here
    passes a freshly rendered canvas, which moves on its own.

    Args:
        svg: The rendered chart, consumed.
        title: The accessible name. Required.
        description: A longer description, omitted when empty.

    Returns:
        The SVG document, titled.

    Raises:
        Error: Whatever `set_title()` raises.
    """
    svg.set_title(title, description)
    return svg.to_string()


def write_accessible_svg(
    var svg: SvgCanvas, path: String, title: String, description: String = ""
) raises:
    """`accessible_svg_string()` written to `path`. See the Cookbook's "SVG
    Accessibility" recipe
    (docs/cookbook_recipes/svg_accessibility.mojo).

    Consumes the canvas, as `accessible_svg_string()` does.
    """
    var f = open(path, "w")
    f.write(accessible_svg_string(svg^, title, description))
    f.close()


def _filled_annotations_go_under(mark: Mark) raises -> Bool:
    """Whether `mark` draws its filled annotations -- `annotate_area()`
    bands and `annotate_band()` ribbons -- *under* its geometry. True
    for the continuous-frame marks, where a ribbon is a region the mark
    is meant to be read through, and drawing it last painted
    `Theme.annotation_area_color` over the line it annotates (#501).
    Those marks draw the fills between frame and mark inside
    `_render_generic`; every other mark still draws them after, from
    `_render_into`/`render_svg`, where a band over solid bars was the
    order it always had.
    """
    return (
        mark == Mark.POINT
        or mark == Mark.LINE
        or mark == Mark.AREA
        or mark == Mark.HISTOGRAM
        or mark == Mark.EFFECT_SCATTER
    )


def _check_render_settings(
    mark: Mark,
    continuous: _ContinuousData,
    channels: _ChannelData,
    y_err: _ErrorBarData,
    annotations: _AnnotationData,
    settings: _ChartSettings,
    has_shared_y_domain: Bool = False,
    shared_y_is_log: Bool = False,
) raises:
    """Every check `_render_generic` makes before it draws, over the
    fields it reads rather than the `Plot` (#828): the settings that
    cannot apply to this mark, an unsupported log or symlog axis, a
    domain, tick or aspect override on a mark that does not honor it,
    and the annotation values a log axis cannot place. Raises the
    same errors it always did."""
    _check_unsupported_flags(
        mark,
        settings.theme,
        settings.horizontal,
        settings.tooltip_policy(),
    )
    _check_missing_policy(settings.theme, continuous, channels)
    if settings.secondary_axis:
        raise Error(
            "Plot.secondary_axis() only applies inside render_layers()/"
            "render_layers_svg() -- a standalone plot has only one"
            " series, nothing for a second y-axis to pair against"
        )
    if settings.y_log and settings.y_symlog:
        raise Error(
            "Plot.scale_y_log()/scale_y_symlog(): an axis cannot be both."
            " A log axis has no zero to be linear around, which is the"
            " whole of what symlog adds -- choose one"
        )
    if settings.x_log and settings.x_symlog:
        raise Error(
            "Plot.scale_x_log()/scale_x_symlog(): an axis cannot be both."
            " A log axis has no zero to be linear around, which is the"
            " whole of what symlog adds -- choose one"
        )
    if (
        settings.y_log
        or settings.x_log
        or settings.y_symlog
        or settings.x_symlog
    ) and not mark.supports(Feature.LOG_X):
        raise Error(
            "Plot.scale_y_log()/scale_x_log() only apply to "
            + _supporting_names(Feature.LOG_X)
            + " -- a categorical-x-axis (or other non-continuous) mark has"
            " no continuous domain for a log scale to mean anything against"
        )
    if settings.y_log and not mark.supports(Feature.LOG_Y):
        raise Error(
            "Plot.scale_y_log(): only "
            + _supporting_names(Feature.LOG_Y)
            + " -- the other marks with a continuous x axis force their"
            " y-domain through a zero baseline (see"
            " _zero_baseline_y_extent()'s docstring), and zero has no logarithm"
        )
    if (settings.x_domain.has or settings.y_domain.has) and not (
        mark == Mark.POINT
        or mark == Mark.LINE
        or mark == Mark.AREA
        or mark == Mark.HISTOGRAM
        or mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            "Plot.scale_x_domain()/scale_y_domain() only apply to"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER today -- a categorical-x-axis"
            " (or other non-continuous) mark isn't wired up to an explicit"
            " domain override yet"
        )
    _validate_domain_override(
        settings.x_domain, settings.x_log, "Plot.scale_x_domain"
    )
    _validate_domain_override(
        settings.y_domain, settings.y_log, "Plot.scale_y_domain"
    )
    if (
        settings.x_tick_override.has
        or settings.y_tick_override.has
        or settings.x_reversed
        or settings.y_reversed
        or settings.equal_aspect
    ) and not (
        mark == Mark.POINT
        or mark == Mark.LINE
        or mark == Mark.AREA
        or mark == Mark.HISTOGRAM
        or mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            "Plot.scale_x_ticks()/scale_y_ticks()/scale_x_reverse()/"
            "scale_y_reverse()/equal_aspect() only apply to"
            " Mark.POINT/LINE/AREA/HISTOGRAM/EFFECT_SCATTER today -- the"
            " other marks reach the continuous frame through their own"
            " renders, which do not carry these yet (#368)"
        )
    _validate_tick_override(
        settings.x_tick_override,
        settings.x_log,
        "Plot.scale_x_ticks",
    )
    _validate_tick_override(
        settings.y_tick_override,
        settings.y_log,
        "Plot.scale_y_ticks",
    )
    if settings.equal_aspect and (settings.x_log or settings.y_log):
        raise Error(
            "Plot.equal_aspect(): not supported on a log-scaled axis -- a"
            " data unit is a different length at each end of a log axis,"
            " so equal pixel lengths for equal data distances is not a"
            " property it can have"
        )
    if settings.equal_aspect and settings.x_time:
        raise Error(
            "Plot.equal_aspect(): not supported on a time axis -- a second"
            " and a unit of y are not comparable lengths, so there is no"
            " aspect to equalize"
        )
    _validate_color_domain(settings.color_domain, mark, channels)
    if has_shared_y_domain and not (
        mark == Mark.POINT
        or mark == Mark.LINE
        or mark == Mark.AREA
        or mark == Mark.HISTOGRAM
        or mark == Mark.EFFECT_SCATTER
    ):
        raise Error(
            "render_facets(shared_y_scale=True): only"
            " Mark.POINT/LINE/AREA/EFFECT_SCATTER support a shared y-scale"
            " today -- a categorical or polar mark has no continuous"
            " y-domain for a shared range to mean anything against"
        )
    if has_shared_y_domain and settings.y_log != shared_y_is_log:
        raise Error(
            "render_facets(shared_y_scale=True): every cell must agree on"
            " Plot.scale_y_log() -- got a mix of log and linear cells"
        )
    if has_shared_y_domain and (
        len(y_err.symmetric) > 0 or len(y_err.lower) > 0 or len(y_err.upper) > 0
    ):
        # The shared union is computed over plain continuous.y and isn't widened
        # for whisker endpoints, so a whisker could extend past the shared
        # axis.
        raise Error(
            "render_facets(shared_y_scale=True): not supported together with"
            " Plot.encode(y_err=...)/y_err_lower/y_err_upper -- the shared"
            " domain isn't widened for whisker endpoints yet"
        )
    _validate_log_scale_annotations(annotations, settings.x_log, settings.y_log)


def _render_continuous[
    T: DrawTarget
](
    mut target: T,
    mark: Mark,
    histogram: _HistogramData,
    continuous: _ContinuousData,
    channels: _ChannelData,
    y_err: _ErrorBarData,
    style: _MarkStyle,
    annotations: _AnnotationData,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    has_shared_y_domain: Bool = False,
    shared_y_min: Float64 = 0.0,
    shared_y_max: Float64 = 0.0,
    shared_y_is_log: Bool = False,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """The continuous-axis path, `Mark.POINT`/`LINE`/`AREA`/
    `EFFECT_SCATTER`/`HISTOGRAM`'s renderer: decide the two domains,
    size the legend column, draw the axis frame, then the mark. Over
    the fields it reads rather than the `Plot` (#828); `_render_generic`
    hands them over after the mark callback declines."""
    _validate_continuous_encoding(
        continuous,
        channels,
        y_err,
        mark,
        "Plot.encode()",
    )
    _require_non_empty(len(continuous.x), "Plot.encode()")

    var theme = settings.theme

    # Scaled once by theme.scale; see _Scaled.
    var sc = _Scaled(theme)

    # Built once and handed to both _legend_reserve_for and
    # _draw_point_layer so the two agree; see _PointChannels.
    var ch = _PointChannels(channels, settings.theme, settings.color_domain, sc)

    var legend_reserve = _legend_reserve_for(
        mark, settings.theme, ch, sc, cache=cache
    )

    # Mark.AREA forces a zero baseline into the y-domain; every other
    # continuous mark pads around its data. y_domain_data is continuous.y,
    # or every whisker endpoint when y_err (or y_err_lower/y_err_upper) is
    # set, so the domain spans everything drawn. has_shared_y_domain
    # (render_facets(shared_y_scale=True)) short-circuits that with the
    # caller's precomputed domain.
    var y_domain_data = List[Float64]()
    if len(y_err.symmetric) > 0:
        for i in range(len(continuous.y)):
            y_domain_data.append(continuous.y[i] - y_err.symmetric[i])
            y_domain_data.append(continuous.y[i] + y_err.symmetric[i])
    elif len(y_err.lower) > 0:
        for i in range(len(continuous.y)):
            y_domain_data.append(continuous.y[i] - y_err.lower[i])
            y_domain_data.append(continuous.y[i] + y_err.upper[i])
    else:
        for v in continuous.y:
            y_domain_data.append(v)
    var y_scale = _domain_override_scale(
        settings.y_domain, settings.y_log
    ) if settings.y_domain.has else (
        LinearScale(
            shared_y_min, shared_y_max, 0.0, 1.0, is_log=shared_y_is_log
        ) if has_shared_y_domain else (
            _log_data_extent(y_domain_data) if settings.y_log else (
                _symlog_data_extent(
                    y_domain_data, settings.y_symlog_linthresh
                ) if settings.y_symlog else (
                    _zero_baseline_y_extent(y_domain_data) if (
                        mark == Mark.AREA
                        or (mark == Mark.HISTOGRAM and not histogram.horizontal)
                    ) else _data_extent(y_domain_data)
                )
            )
        )
    )
    # A horizontal histogram's values run along x, so x takes the zero
    # baseline its y would have had.
    var x_scale = _domain_override_scale(
        settings.x_domain, settings.x_log
    ) if settings.x_domain.has else (
        _log_data_extent(continuous.x) if settings.x_log else (
            _symlog_data_extent(
                continuous.x, settings.x_symlog_linthresh
            ) if settings.x_symlog else (
                _zero_baseline_y_extent(continuous.x) if (
                    mark == Mark.HISTOGRAM and histogram.horizontal
                ) else _data_extent(continuous.x)
            )
        )
    )
    # A time axis is linear in seconds; only its labels differ, so the
    # domain is whatever the branches above computed and the flag simply
    # rides along to `LinearScale.ticks()`.
    if settings.x_time:
        x_scale.is_time = True
        x_scale.tz_offset = settings.x_tz_offset

    var controls = _AxisControls()
    controls.x_ticks = settings.x_tick_override.copy()
    controls.y_ticks = settings.y_tick_override.copy()
    controls.x_reversed = settings.x_reversed
    controls.y_reversed = settings.y_reversed
    controls.equal_aspect = settings.equal_aspect
    var frame = _draw_continuous_axis_frame(
        target,
        x_scale,
        y_scale,
        theme,
        legend_reserve,
        ox0,
        oy0,
        ox1,
        oy1,
        controls=controls,
        cache=cache,
    )

    # Filled annotations go under the mark (#501): the area bands and
    # ribbons are drawn now, against the finished frame, so the mark is
    # read through them rather than painted over by them. Their labels
    # join the frame's text requests and are replayed with the rest.
    # Stroked and text annotations still draw after the mark.
    var under = frame.result()
    var under_areas = _draw_annotation_areas(
        target, annotations, under, theme, cache=cache
    )
    for k in range(len(under_areas)):
        frame.text_requests.append(under_areas[k].copy())
    var under_bands = _draw_annotation_bands(
        target, annotations, under, theme, cache=cache
    )
    for k in range(len(under_bands)):
        frame.text_requests.append(under_bands[k].copy())

    if mark == Mark.POINT or mark == Mark.EFFECT_SCATTER:
        _ = _draw_point_layer(
            target,
            frame.text_requests,
            mark,
            continuous,
            channels,
            y_err,
            style,
            settings,
            ch,
            frame.x_scale,
            frame.y_scale,
            _legend_origin_x(legend_reserve, frame.px0, frame.px1, sc),
            _legend_origin_y(legend_reserve, frame.py0, frame.py1, sc),
            draw_halo=mark == Mark.EFFECT_SCATTER,
            legend_horizontal=legend_reserve.position.is_horizontal(),
            cache=cache,
        )
    elif mark == Mark.LINE:
        _draw_line_layer(
            target,
            continuous,
            y_err,
            style,
            settings,
            frame.x_scale,
            frame.y_scale,
        )
    elif mark == Mark.AREA:
        _draw_area_layer(
            target,
            continuous,
            style,
            settings,
            frame.x_scale,
            frame.y_scale,
        )
    elif mark == Mark.HISTOGRAM:
        _draw_histogram_layer(
            target,
            histogram,
            settings,
            frame.x_scale,
            frame.y_scale,
            frame.text_requests,
        )

    return frame.result()
