"""`render_layers()`: several plots sharing one frame.

Split out of `plot.mojo`. Layering is not just drawing twice --
the layers have to agree on a domain, a legend column and one set of
axis furniture before any of them draws, which is what
`_render_layers_generic` resolves.

`_render_bar_combo_layers` is the special case worth knowing about: a
bar layer owns a categorical x, so the continuous layers over it are
placed against that categorical frame's band centers rather than
against a continuous scale of their own.
"""

from std.math import pi

from canvas.buffer import Canvas
from canvas.color import Color
from canvas.fill_rule import FillRule
from canvas.geometry import round_to_int
from canvas.io.bmp import write_bmp
from canvas.io.png import write_png
from canvas.resize import downsample
from canvas.text.font_cache import FontCache
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget
from canvas.vector.svg import SvgCanvas

from dataviz.annotations import (
    _draw_annotation_areas,
    _draw_annotation_bands,
    _draw_annotation_best_fit,
    _draw_annotation_lines,
    _draw_annotation_points,
    _draw_annotation_vlines,
    _validate_log_scale_annotations,
)
from dataviz.bar import _bar_y_domain_data, _draw_bar_rects, _render_bar
from dataviz.barbs import _draw_barbs_layer, _validate_barbs
from dataviz.histogram import _draw_histogram_layer
from dataviz.continuous import (
    _PointChannels,
    _build_line_path,
    _draw_area_layer,
    _draw_line_layer,
    _draw_point_layer,
    _step_points,
    area,
    line,
)
from dataviz.facets import _require_uniform_size
from dataviz.frame import (
    _Orientation,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _draw_continuous_axis_frame,
    _with_secondary_axis,
)
from dataviz.ecdf import _draw_ecdf_layer, _ecdf_points
from dataviz.kde import (
    _draw_kde_layer,
    _draw_rug_ticks,
    _kde_curve,
    _kde_observations,
)
from dataviz.legend import (
    _LegendLayout,
    _draw_legend,
    _dynamic_legend_width,
    _legend_reserve_for,
)
from dataviz.legend_position import LegendPosition
from dataviz.mark import Mark
from dataviz.output_format import OutputFormat
from dataviz.plot import (
    _DomainOverride,
    _require_non_empty,
    _resolve_supersample,
    Plot,
    _RenderResult,
    _data_extent,
    _log_data_extent,
    _render_generic,
    _render_into,
    _require_positive_supersample,
    _resolve_output_format,
    _svg_output_string,
    _zero_baseline_y_extent,
    render,
    save,
)
from dataviz.scale import LinearScale
from dataviz.text import (
    _Scaled,
    _TextRequest,
    _apply_labels,
    _extend_text_requests,
    _label_text_requests,
    _max_label_width,
    _replay_text_requests,
    _replay_text_requests_svg,
)
from dataviz.theme import Theme
from dataviz.tricontour import (
    _draw_tricontour_layer,
    _draw_tricontourf_layer,
    _validate_tricontour,
)
from dataviz.triplot import (
    _draw_tripcolor_layer,
    _draw_triplot_layer,
    _validate_tripcolor,
    _validate_triplot,
)
from dataviz.validate import (
    _check_line_smoothing,
    _check_step_smoothing,
    _domain_override_scale,
    _validate_color_domain,
    _validate_domain_override,
    _validate_categorical_encoding,
    _validate_continuous_encoding,
)


def save_layers(plots: List[Plot], path: String) raises:
    """`save()`'s `render_layers()`/`render_layers_svg()` counterpart. The
    format comes from `plots[0]`'s theme when the path's extension
    doesn't decide it. Raises on an empty `plots`.

    SVG output writes accessible markup automatically from
    `plots[0]`'s `.labels()`, the same one whose title/subtitle
    `render_layers()` itself draws (only the first layer's labels apply
    to a layered chart); see `save()`'s own docstring.
    """
    if len(plots) == 0:
        raise Error("save_layers(): plots must not be empty")
    var format = _resolve_output_format(plots[0]._theme.output_format, path)
    if format == OutputFormat.SVG:
        var f = open(path, "w")
        f.write(_svg_output_string(render_layers_svg(plots), plots[0]._labels))
        f.close()
    elif format == OutputFormat.PNG:
        write_png(render_layers(plots), path)
    else:
        write_bmp(render_layers(plots), path)


def _secondary_axis_y_title(plots: List[Plot]) -> String:
    """`render_layers()`'s secondary (right) y-axis caption: the first
    layer's `Plot.labels()` `y_title` where that layer also called
    `.secondary_axis()`, read per-layer rather than from `plots[0]`'s
    shared chrome. Empty when no secondary-axis layer set one.
    """
    for i in range(len(plots)):
        if (
            plots[i]._secondary_axis
            and plots[i]._labels.y_title.byte_length() > 0
        ):
            return plots[i]._labels.y_title
    return ""


def render_layers(plots: List[Plot]) raises -> Canvas:
    """Render every `Plot` in `plots` onto one shared coordinate system: one
       combined x/y domain across every layer, one set of axes/gridlines/
       ticks, each mark drawn over the last in the order given.

       Takes the marks that place their data on a continuous x/y axis in the
       caller's own units, which is what one shared domain can mean:
       `Mark.POINT`, `LINE`, `AREA`, `EFFECT_SCATTER`, `KDE`, `RUG`,
       `BARBS`, `TRICONTOUR`, `TRICONTOURF`, `TRIPLOT` and `TRIPCOLOR`
    -- so a rug under a density curve, two KDEs compared on one
       frame, isolines over a filled contour, or a scatter over a
       triangulated field all draw. Plus at most one `Mark.BAR` layer for a
       bar-plus-line combo chart (dispatched to `_render_bar_combo_layers`,
       which has a narrower scope).

       Every other mark raises with the reason: a categorical, polar,
       hierarchical or edge-list mark has no continuous x to share;
       `Mark.CONTOUR`/`CONTOURF` lay out in unpadded grid-index units rather
       than the data's own coordinates; `Mark.SINGLE_AXIS` pins its
       points at the plot rect's vertical midpoint, which encodes nothing.
       `render_facets()` has no allow-list at all and takes any mark, so it
       is what to reach for when a composition here is refused.

       A `Plot.secondary_axis()` layer scales against its own y-domain on
       the right edge -- not a `Mark.RUG` layer, which has no y dimension to
       scale. A `Mark.POINT`/`EFFECT_SCATTER` layer may use `color`/
       `color_categories`/`size` encoding with its own scales and legend
       section; sections stack in one column in layer order. There is no
       per-series legend for flat-colored layers, and the field marks draw
       no color bar here, as they draw none standalone.

       Domains combine across every layer: the x-axis spans all of them, and
       a layer whose y is measured from a baseline -- `Mark.AREA`'s fill
       height, `Mark.KDE`'s density -- forces zero into its axis group's
       domain, the rule one `Mark.AREA` layer has always applied.
       `Plot.scale_x_log()`/`scale_y_log()` apply only to `Mark.POINT`/
       `LINE`/`AREA`/`EFFECT_SCATTER`, the same restriction a standalone
       render has. A stack of nothing but `Mark.RUG` layers has no y-axis
       at all and draws none, as a standalone `rugplot()` does.

       Shared chrome (background, gridlines, axis colors, margins, font
       size, `Plot.labels()` titles) comes from `plots[0]`; every other
       layer's `Theme` governs only its own mark (`mark_color`,
       `point_radius`, `line_width`, `line_smoothing`, scaled by its own
       `Theme.scale`). A secondary-axis layer's `y_title` captions the right
       axis.

       Every `Plot` must share the same `.size()`; an empty list raises.
       Supersampled by `plots[0]._theme.raster_supersample` like `render()`,
       bumping every layer's scale together on a copy (`plots` is a plain
       borrow).
    """
    _require_uniform_size(plots, "render_layers")
    # One canvas, so one factor must serve every plot on it: take the
    # largest any of them asks for rather than the first plot's, or a
    # curved mark beside a bar chart would be drawn at the bar's factor.
    var factor = _resolve_supersample(plots[0], "render_layers")
    for i in range(1, len(plots)):
        var f = _resolve_supersample(plots[i], "render_layers")
        if f > factor:
            factor = f
    var canvas = Canvas(plots[0].width, plots[0].height)
    # `begin_supersampled` owns the half-pixel shift box downsampling
    # costs and the scale, and replays the recorded shapes one output
    # band at a time, so the enlarged buffer never exists whole. Byte
    # identical to the two-step recipe it replaces (canvas_mojo#391).
    canvas.begin_supersampled(factor)
    # Logical bounds; the transform maps them up. See render().
    var cx1 = plots[0].width
    var cy1 = plots[0].height
    canvas.fill_rect(0, 0, cx1, cy1, plots[0]._theme.background)
    var sc = _Scaled(plots[0]._theme)
    var y2_title = _secondary_axis_y_title(plots)
    var frame = _apply_labels(plots[0], 0, 0, cx1, cy1)
    if y2_title.byte_length() > 0:
        # Mirrors _apply_labels's extra_left reservation for the primary
        # y_title, on the right edge; _apply_labels only sees plots[0], not the
        # layer that owns the secondary caption.
        frame.ox1 -= Int(sc.axis_title_font_size) + sc.label_gap
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    var result = _render_layers_generic(
        canvas,
        plots,
        frame.ox0,
        frame.oy0,
        frame.ox1,
        frame.oy1,
        cache=cache,
    )
    var label_requests = _label_text_requests(
        plots[0],
        0,
        0,
        cx1,
        cy1,
        result.px0,
        result.py0,
        result.px1,
        result.py1,
    )
    if y2_title.byte_length() > 0:
        # The mirror of _label_text_requests's primary y_title: rotated +pi/2
        # (reading top-to-bottom, the right-side convention) and anchored to
        # the outer right edge.
        label_requests.append(
            _TextRequest(
                cx1 - Int(sc.axis_title_font_size * 0.8),
                (result.py0 + result.py1) // 2,
                y2_title,
                plots[0]._theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
                plots[0]._theme.font_family,
                rotation=pi / 2.0,
            )
        )
    _replay_text_requests(canvas, label_requests, cache)
    _replay_text_requests(canvas, result.text_requests, cache)
    canvas.end_supersampled()
    return canvas^


def render_layers_svg(plots: List[Plot]) raises -> SvgCanvas:
    """`render_layers()`'s counterpart for `SvgCanvas`, with the same
    `_render_layers_generic` core and `_require_uniform_size`
    precondition.
    """
    _require_uniform_size(plots, "render_layers_svg")
    var svg = SvgCanvas(plots[0].width, plots[0].height)
    var cx1 = svg.width
    var cy1 = svg.height
    svg.fill_rect(0, 0, cx1, cy1, plots[0]._theme.background)
    var sc = _Scaled(plots[0]._theme)
    var y2_title = _secondary_axis_y_title(plots)
    var frame = _apply_labels(plots[0], 0, 0, cx1, cy1)
    if y2_title.byte_length() > 0:
        frame.ox1 -= Int(sc.axis_title_font_size) + sc.label_gap
    # One lazily built FontCache for the whole figure; see _render_into.
    var cache = FontCache()
    var result = _render_layers_generic(
        svg, plots, frame.ox0, frame.oy0, frame.ox1, frame.oy1, cache=cache
    )
    var label_requests = _label_text_requests(
        plots[0], 0, 0, cx1, cy1, result.px0, result.py0, result.px1, result.py1
    )
    if y2_title.byte_length() > 0:
        label_requests.append(
            _TextRequest(
                cx1 - Int(sc.axis_title_font_size * 0.8),
                (result.py0 + result.py1) // 2,
                y2_title,
                plots[0]._theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
                plots[0]._theme.font_family,
                rotation=pi / 2.0,
            )
        )
    _replay_text_requests_svg(svg, label_requests)
    _replay_text_requests_svg(svg, result.text_requests)
    return svg^


def _render_bar_combo_layers[
    T: DrawTarget
](
    mut target: T,
    plots: List[Plot],
    bar_index: Int,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """`_render_layers_generic`'s dispatch target when exactly one layer is
    `Mark.BAR`: a bar-plus-line combo chart sharing the bar layer's
    categorical x-axis instead of a continuous one.

    Every non-bar layer aligns to the categories by position:
    `plots[j].y_data[k]` plots at category `k`'s band center, and its
    `x_data` must have exactly `len(bar_categories)` entries (checked
    here) but its numeric content is never read; callers commonly pass
    `x=[0.0, 1.0, 2.0, ...]`.

    Scope: no `color`/`color_categories`/`size`/`y_err*`/`labels`
    encoding on non-bar layers, no `Plot.secondary_axis()`/
    `scale_y_log()`/`scale_x_log()`/`mark_bar(horizontal=True)`, and no
    `Plot.annotate_*()` on any layer; each raises. The bar layer keeps
    its own `Theme.color_by_sign`/`show_data_labels` through
    `_draw_bar_rects`.

    The bar layer always draws first, beneath every other layer,
    regardless of its position in `plots`; the others draw in order, each
    in its own `Theme`. The shared y-domain always includes a zero
    baseline (`_zero_baseline_y_extent`), as `Mark.BAR` requires.
    """
    var bar_categories = plots[bar_index].x_categories.copy()
    _validate_categorical_encoding(plots[bar_index])

    for i in range(len(plots)):
        if plots[i]._secondary_axis:
            raise Error(
                "render_layers(): Plot.secondary_axis() isn't supported yet on"
                " a Mark.BAR combo chart (layer "
                + String(i)
                + ")"
            )
        if plots[i]._y_log or plots[i]._x_log:
            raise Error(
                "render_layers(): Plot.scale_y_log()/scale_x_log() aren't"
                " supported yet on a Mark.BAR combo chart (layer "
                + String(i)
                + ")"
            )
        if plots[i]._horizontal:
            raise Error(
                "render_layers(): Plot.mark_bar(horizontal=True) isn't"
                " supported yet on a Mark.BAR combo chart (layer "
                + String(i)
                + ") -- a horizontal categorical axis alongside continuous"
                " line/point/area layers is a real, separate feature this"
                " doesn't attempt"
            )
        var has_annotations = (
            len(plots[i]._annotations.line_values) > 0
            or len(plots[i]._annotations.area_y0) > 0
            or len(plots[i]._annotations.vline_values) > 0
            or len(plots[i]._annotations.point_x) > 0
            or len(plots[i]._annotations.band_x) > 0
            or plots[i]._annotations.best_fit
        )
        if has_annotations:
            raise Error(
                "render_layers(): Plot.annotate_*() isn't supported yet on a"
                " Mark.BAR combo chart (layer "
                + String(i)
                + ")"
            )
        if i == bar_index:
            continue
        if not (
            plots[i]._mark == Mark.POINT
            or plots[i]._mark == Mark.LINE
            or plots[i]._mark == Mark.AREA
        ):
            raise Error(
                "render_layers(): alongside a Mark.BAR layer, every other layer"
                " must be Mark.POINT/LINE/AREA (layer "
                + String(i)
                + ")"
            )
        if len(plots[i].x_data) != len(bar_categories):
            raise Error(
                "render_layers(): with a Mark.BAR layer present, every other"
                " layer's own data must have one entry per bar category --"
                " layer "
                + String(i)
                + " has "
                + String(len(plots[i].x_data))
                + " points, the bar layer has "
                + String(len(bar_categories))
                + " categories"
            )
        if len(plots[i].y_data) != len(plots[i].x_data):
            raise Error(
                "render_layers(): layer "
                + String(i)
                + ": x and y must have the same length (got "
                + String(len(plots[i].x_data))
                + " and "
                + String(len(plots[i].y_data))
                + ")"
            )
        if (
            len(plots[i].color_data) > 0
            or len(plots[i].color_categories) > 0
            or len(plots[i].size_data) > 0
            or len(plots[i].y_err_data) > 0
            or len(plots[i].y_err_lower_data) > 0
            or len(plots[i].y_err_upper_data) > 0
            or len(plots[i].point_labels) > 0
        ):
            raise Error(
                "render_layers():"
                " color/color_categories/size/y_err/y_err_lower/y_err_upper/labels"
                " encoding isn't supported yet on a Mark.BAR combo chart's"
                " non-bar layers (layer "
                + String(i)
                + ")"
            )

    # The bar layer's own y_err/y_err_lower/y_err_upper, allowed here
    # since _validate_categorical_encoding above already restricts them to
    # Mark.BAR) widens the shared domain to its whisker endpoints, same as
    # the standalone _render_bar does; every other layer's y_err* is
    # rejected above, so its own y_data is all it ever contributes.
    var combined_y = List[Float64]()
    for i in range(len(plots)):
        if i == bar_index:
            for v in _bar_y_domain_data(plots[i]):
                combined_y.append(v)
        else:
            for v in plots[i].y_data:
                combined_y.append(v)
    var y_scale = _zero_baseline_y_extent(combined_y)

    var theme = plots[0]._theme
    var sc = _Scaled(theme)

    # one legend row per named layer (Plot.series_name()), the bar
    # layer included, each in that layer's own Theme.mark_color.
    var series_names = List[String]()
    var series_colors = List[Color]()
    for i in range(len(plots)):
        if plots[i]._labels.series_name.byte_length() > 0:
            series_names.append(plots[i]._labels.series_name)
            series_colors.append(plots[i]._theme.mark_color)
    var legend_reserve = (
        _dynamic_legend_width(
            series_names, sc.legend_swatch_size, sc, cache=cache
        ) if len(series_names)
        > 0 else 0
    )

    var frame = _draw_categorical_axis_frame(
        target,
        bar_categories,
        y_scale,
        theme,
        ox0,
        oy0,
        ox1 - legend_reserve,
        oy1,
        cache=cache,
    )
    if len(series_names) > 0:
        _draw_legend(
            target,
            frame.text_requests,
            series_names,
            series_colors,
            frame.px1 + sc.margin_right,
            frame.py0,
            theme,
        )

    _draw_bar_rects(
        target,
        plots[bar_index],
        frame.x_scale,
        frame.y_scale,
        frame.py1,
        _Orientation(False),
        frame.text_requests,
    )

    for i in range(len(plots)):
        if i == bar_index:
            continue
        var layer_theme = plots[i]._theme
        _check_line_smoothing(layer_theme)
        var layer_sc = _Scaled(layer_theme)
        # Precomputed band centers instead of a continuous x_scale --
        # the one thing a categorical frame has that no LinearScale can
        # express, and the reason this path used to reimplement each
        # mark's geometry. The three shared draw functions take these
        # directly now (#422), so there is exactly one copy of every
        # mark's drawing code and a styling argument added to one of
        # them cannot go missing here.
        #
        # That had already happened three times: mark_line(step=...)
        # (#336), mark_line(style=...) (#383) and
        # mark_point(tooltips=True) (#422), each found only after it
        # shipped, because a dropped argument renders a different claim
        # about the data rather than an error.
        var band_px = List[Float64](capacity=len(plots[i].y_data))
        for k in range(len(plots[i].y_data)):
            band_px.append(frame.x_scale.center(k))

        # Decimation is a no-op here rather than something to suppress:
        # one x per category means there is never more than one sample
        # per pixel column to thin, so _decimate_to_pixel_columns keeps
        # every point. color/size/y_err/labels are rejected above, so
        # the shared functions' handling of them is unreachable, not
        # bypassed.
        if plots[i]._mark == Mark.POINT:
            # x_scale is unused whenever band_px is supplied, but the
            # signature is shared with the continuous path, so a
            # placeholder domain goes in rather than an Optional.
            var unused_x = LinearScale(0.0, 1.0, 0.0, 1.0)
            var ch = _PointChannels(plots[i], layer_sc)
            var unused_legend = List[_TextRequest]()
            _ = _draw_point_layer(
                target,
                unused_legend,
                plots[i],
                ch,
                unused_x,
                frame.y_scale,
                0,
                0,
                band_px=band_px,
            )
        elif plots[i]._mark == Mark.LINE:
            _draw_line_layer(
                target,
                plots[i],
                LinearScale(0.0, 1.0, 0.0, 1.0),
                frame.y_scale,
                band_px,
            )
        else:
            _draw_area_layer(
                target,
                plots[i],
                LinearScale(0.0, 1.0, 0.0, 1.0),
                frame.y_scale,
                band_px,
            )

    return frame.result()


def _merge_override(
    mut into: _DomainOverride,
    override: _DomainOverride,
    layer: Int,
    context: String,
) raises:
    """Adopt `override` as the layers' shared explicit domain, or raise
    if an earlier layer already asked for a different one. Two layers
    that disagree have no shared axis, and the message names both
    values rather than refusing overrides wholesale (#434).
    """
    if not into.has:
        into = override.copy()
        return
    if into.min != override.min or into.max != override.max:
        raise Error(
            "render_layers(): every layer that sets "
            + context
            + "() must agree on it -- layer "
            + String(layer)
            + " asks for ["
            + String(override.min)
            + ", "
            + String(override.max)
            + "] but an earlier layer asked for ["
            + String(into.min)
            + ", "
            + String(into.max)
            + "]"
        )


def _is_layerable_mark(mark: Mark) raises -> Bool:
    """Whether `mark` can share `_render_layers_generic`'s continuous
    frame.

    The rule is not "does this mark call `_draw_continuous_axis_frame`"
    -- `Mark.CONTOUR` does and is still excluded. It is **does this mark
    place its data on a continuous x/y axis in the caller's own units,
    sized by `_data_extent`**. That is what makes one combined domain
    mean the same thing to every layer, which is the only thing layering
    can be. The twelve below all satisfy it; everything else fails it for
    one of three reasons:

    - **A categorical x** (BAR beyond the bar-combo special case,
      LOLLIPOP, BOX, VIOLIN, BEESWARM, GROUPED_BAR, STACKED_BAR,
      WATERFALL, CANDLESTICK, BULLET, GANTT, SPAN_CHART,
      POPULATION_PYRAMID, FUNNEL, BUMP, STREAMGRAPH, RIDGELINE,
      MARIMEKKO, and the two-categorical-axis marks HEATMAP, CORRPLOT,
      PUNCHCARD, CALENDAR_HEATMAP): a band index is not a coordinate, so
      there is nothing for a continuous layer to line up against.
      `_render_bar_combo_layers` is the one case where this was worth
      solving, and it solves it the other way round -- the continuous
      layers move onto the bar's band centers.
    - **A different geometry entirely** (ARC, NIGHTINGALE, POLAR,
      POLAR_BAR, RADIALBAR, RADAR, GAUGE, PARALLEL, SUNBURST, TREE,
      TREEMAP, CHORD, ARC_DIAGRAM, GRAPH, SANKEY): polar, hierarchical
      or edge-list layouts have no rectangular x/y frame at all.
      `Mark.SINGLE_AXIS` belongs here too -- it draws on
      `_draw_single_axis_frame` and pins its points at the rect's
      vertical midpoint, which encodes nothing and would mean nothing
      against a co-layer's real y-axis.
    - **Grid-index units** (CONTOUR, CONTOURF): continuous, unpadded, and
      spanning the rect edge to edge in *column and row numbers* rather
      than the data's own coordinates. Sharing an axis with a coordinate
      mark would silently equate column 12 with the value 12, and even a
      contour-over-contourf stack needs an unpadded combined domain this
      path has no rule for.

    A `raises` `def` only because `Mark.__eq__` is one.
    """
    return (
        mark == Mark.POINT
        or mark == Mark.LINE
        or mark == Mark.AREA
        or mark == Mark.HISTOGRAM
        or mark == Mark.EFFECT_SCATTER
        or mark == Mark.KDE
        or mark == Mark.ECDF
        or mark == Mark.RUG
        or mark == Mark.BARBS
        or mark == Mark.TRICONTOUR
        or mark == Mark.TRICONTOURF
        or mark == Mark.TRIPLOT
        or mark == Mark.TRIPCOLOR
    )


struct _LayerDomain(Copyable, Movable):
    """One layer's contribution to `render_layers()`'s combined x/y
    domain, plus how that layer wants its y-axis anchored.

    Marks reach the shared frame from four different data fields --
    `Plot.encode()`'s `x_data`/`y_data`, `_distribution.values`,
    `_tricontour.x`/`y`, `_triplot.x`/`y`, `_barbs.x`/`y` -- so the
    domain pass reads them through `_layer_domain` once and works in
    plain columns from there, rather than branching on the mark at every
    place a domain is touched.
    """

    var xs: List[Float64]
    """This layer's x column, exactly as its standalone render would take
    `_data_extent` over. For `Mark.KDE` that is the density curve's
    evaluation points, not the raw observations: the curve runs three
    bandwidths past the data on each side, and cutting the domain at the
    data would clip the curve mid-slope."""

    var ys: List[Float64]
    """This layer's y column, already widened to the whisker endpoints
    when `Plot.encode(y_err=...)`/`y_err_lower`/`y_err_upper` is set, as
    `_render_generic`'s `y_domain_data` does for a standalone plot.
    Empty for `Mark.RUG`, which has no y dimension at all.

    For `Mark.KDE` this is the density at each of `xs`, which is also
    exactly the geometry the draw pass strokes -- it reads these two
    columns back rather than calling `_kde_curve` a second time, so the
    curve drawn is provably the curve the domain was sized for."""

    var zero_baseline: Bool
    """Whether this layer needs zero inside its axis
    (`_zero_baseline_y_extent` rather than `_data_extent`). True for
    `Mark.AREA`, whose fill height is measured from a baseline, and for
    `Mark.KDE`, whose standalone `LinearScale(0.0, y_max * 1.05)` is
    what `_zero_baseline_y_extent` returns for a strictly positive
    column -- so a lone KDE layer reproduces its standalone frame
    exactly. One such layer anywhere in an axis group forces the
    baseline for that whole group, the rule `Mark.AREA` already had."""

    def __init__(
        out self,
        var xs: List[Float64],
        var ys: List[Float64],
        zero_baseline: Bool,
    ):
        self.xs = xs^
        self.ys = ys^
        self.zero_baseline = zero_baseline


def _layer_domain(plot: Plot) raises -> _LayerDomain:
    """One layer's `_LayerDomain`, with that mark's own pre-draw checks
    run first.

    The checks have to happen here rather than inside the drawing: the
    combined domain is built in a pass over every layer *before* the
    shared frame exists, so a `Mark.TRICONTOUR` layer with mismatched
    x/y/z columns has to be caught before `_data_extent` sees them. Each
    mark's validator is the same free function its `_render_*` calls, so
    a bad layer raises the message a standalone render of it would.
    """
    var mark = plot._mark
    if mark == Mark.KDE:
        var values = _kde_observations(plot)
        var curve = _kde_curve(
            values, plot._distribution.kde_bandwidth_override
        )
        return _LayerDomain(curve[0].copy(), curve[1].copy(), True)
    if mark == Mark.ECDF:
        # The staircase's own vertices, exactly what _render_ecdf strokes,
        # so the drawn curve is the curve the axis was sized for. Its y
        # is a proportion; zero_baseline keeps 0 on the axis when an
        # ECDF shares a group with another mark, and a group that is
        # all ECDFs pins the axis to [0, 1] outright (see the scale
        # block in _render_layers_generic).
        _require_non_empty(len(plot._distribution.values), "Plot.encode_ecdf()")
        var observations = plot._distribution.values[0].copy()
        _require_non_empty(len(observations), "Plot.encode_ecdf()")
        var curve = _ecdf_points(
            observations, plot._distribution.ecdf_complementary
        )
        return _LayerDomain(curve.x.copy(), curve.y.copy(), True)
    if mark == Mark.RUG:
        return _LayerDomain(_kde_observations(plot), List[Float64](), False)
    if mark == Mark.BARBS:
        _validate_barbs(plot)
        return _LayerDomain(plot._barbs.x.copy(), plot._barbs.y.copy(), False)
    if mark == Mark.TRICONTOUR or mark == Mark.TRICONTOURF:
        _validate_tricontour(
            plot,
            "Plot.mark_tricontour()" if mark
            == Mark.TRICONTOUR else "Plot.mark_tricontourf()",
        )
        return _LayerDomain(
            plot._tricontour.x.copy(), plot._tricontour.y.copy(), False
        )
    if mark == Mark.TRIPLOT:
        _validate_triplot(plot)
        return _LayerDomain(
            plot._triplot.x.copy(), plot._triplot.y.copy(), False
        )
    if mark == Mark.TRIPCOLOR:
        _validate_tripcolor(plot)
        return _LayerDomain(
            plot._triplot.x.copy(), plot._triplot.y.copy(), False
        )

    # Mark.POINT/LINE/AREA/EFFECT_SCATTER: Plot.encode()'s own columns.
    # A layer's y_err/y_err_lower+y_err_upper widens its contribution to
    # each whisker's endpoints, so the shared axis spans everything
    # drawn, exactly as _render_generic's y_domain_data does.
    var ys = List[Float64]()
    if len(plot.y_err_data) > 0:
        for i in range(len(plot.y_data)):
            ys.append(plot.y_data[i] - plot.y_err_data[i])
            ys.append(plot.y_data[i] + plot.y_err_data[i])
    elif len(plot.y_err_lower_data) > 0:
        for i in range(len(plot.y_data)):
            ys.append(plot.y_data[i] - plot.y_err_lower_data[i])
            ys.append(plot.y_data[i] + plot.y_err_upper_data[i])
    else:
        for v in plot.y_data:
            ys.append(v)
    if mark == Mark.HISTOGRAM and plot._histogram.horizontal:
        raise Error(
            "render_layers(): a horizontal Mark.HISTOGRAM layer isn't"
            " supported -- the combined domain zero-baselines y, not x."
            " Use render_facets(), or a vertical histogram."
        )
    return _LayerDomain(
        plot.x_data.copy(), ys^, mark == Mark.AREA or mark == Mark.HISTOGRAM
    )


def _render_layers_generic[
    T: DrawTarget
](
    mut target: T,
    plots: List[Plot],
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """The shared-domain layout/draw core `render_layers()`/
    `render_layers_svg()` delegate to, built from the same pieces
    `_render_generic` uses: `_draw_continuous_axis_frame` for the frame,
    then each layer's own `_draw_*_layer` for its geometry. What differs:
    domains computed across every layer's data (`_layer_domain`), a
    legend column sized across every layer with a legend-y cursor
    threaded through in order, and an optional secondary axis. Exactly
    one `Mark.BAR` layer dispatches to `_render_bar_combo_layers` first.

    `_is_layerable_mark` is the allow-list and its docstring carries the
    reasoning. Every admitted mark has its geometry after
    its frame call extracted into a `_draw_*_layer` free function that
    takes an already-ranged `x_scale`/`y_scale`, and both its `_render_*`
    and this call it. Nothing here reimplements a mark. That is the one
    rule `_render_bar_combo_layers` broke, and it has cost three silently
    dropped styling arguments.

    A `Plot.secondary_axis()` layer is excluded from the primary y-domain
    and gets its own (zero-baselined if any layer in its group is
    `Mark.AREA`, else `_data_extent`), drawn mirrored on the right edge
    (axis line, ticks, labels, no gridlines) with its width reserved
    between the plot rect and the legend column. Each layer's own
    `annotate_*()` (areas, bands, lines, vlines, points, best_fit) draw
    last against that layer's own y-scale and the one shared x-scale
    (there is no secondary x-axis). Returns a `_RenderResult` whose inner
    rect centers `plots[0]`'s titles.

    Not reached by a `Mark.BAR` combo chart (`_render_bar_combo_layers`,
    dispatched below before any of this runs): that path rejects every
    `annotate_*()` kind outright rather than drawing them against its
    categorical x-axis.
    """
    var text_requests = List[_TextRequest]()
    if len(plots) == 0:
        return _RenderResult(text_requests^, ox0, oy0, ox1, oy1)

    # Exactly one Mark.BAR layer dispatches to _render_bar_combo_layers (a
    # categorical x-axis is a different domain shape from this continuous
    # path). More than one has no shared-axis meaning and is rejected
    # first.
    var bar_layer_count = 0
    var bar_layer_index = -1
    for i in range(len(plots)):
        if plots[i]._mark == Mark.BAR:
            bar_layer_count += 1
            bar_layer_index = i
    if bar_layer_count > 1:
        raise Error(
            "render_layers(): at most one Mark.BAR layer is supported (got "
            + String(bar_layer_count)
            + ") -- combining several categorical bar layers has no principled"
            " shared-axis meaning yet"
        )
    if bar_layer_count == 1:
        return _render_bar_combo_layers(
            target, plots, bar_layer_index, ox0, oy0, ox1, oy1, cache=cache
        )

    # Log-ness is decided per axis -- x is shared by every layer
    # (there is no secondary x-axis), while y splits into the primary
    # group and the Plot.secondary_axis() group, each independently. Every
    # layer sharing an axis must agree; the first layer on each axis sets
    # that axis's value and every later one is checked against it, so the
    # raised message names the first layer that disagrees.
    var x_override = _DomainOverride()
    var y_override = _DomainOverride()
    var x_log_seen = False
    var x_log_value = False
    var y_log_seen = False
    var y_log_value = False
    var y2_log_seen = False
    var y2_log_value = False
    var domains = List[_LayerDomain](capacity=len(plots))
    for i in range(len(plots)):
        # Layering-specific check: a standalone Mark.BAR is legal, a layered
        # one alongside these isn't. A lone Mark.BAR already dispatched above,
        # so this fires only for marks with no continuous frame of their own.
        #
        # The message names both the offending layer's index and its
        # mark because several mark docstrings tell callers to
        # layer marks this rejects, and a reader who followed one got a
        # message that named neither.
        # constants and the index was all a raise could report.
        if not _is_layerable_mark(plots[i]._mark):
            raise Error(
                "render_layers(): layer "
                + String(i)
                + " is "
                + plots[i]._mark.name()
                + ", which can't share a continuous frame. Layerable marks"
                " are Mark.POINT, LINE, AREA, EFFECT_SCATTER, KDE, RUG,"
                " BARBS, TRICONTOUR, TRICONTOURF, TRIPLOT and TRIPCOLOR --"
                " every one of them places its data on a continuous x/y axis"
                " in the caller's own units, which is what one shared domain"
                " can mean. Mark.BAR is supported only as the lone"
                " categorical layer in a bar-combo chart (see"
                " _render_bar_combo_layers). A categorical, polar,"
                " hierarchical or edge-list mark has no continuous x to"
                " share; Mark.CONTOUR/CONTOURF lay out in unpadded"
                " grid-index units rather than the data's own coordinates"
                "; Mark.SINGLE_AXIS pins its points at the rect's"
                " midpoint, which would mean nothing against a co-layer's"
                " real y-axis. Use render_facets(), which has no allow-list"
                " and takes any mark."
            )
        if (plots[i]._x_log or plots[i]._y_log) and not (
            plots[i]._mark == Mark.POINT
            or plots[i]._mark == Mark.LINE
            or plots[i]._mark == Mark.AREA
            or plots[i]._mark == Mark.HISTOGRAM
            or plots[i]._mark == Mark.EFFECT_SCATTER
        ):
            # The same rule _render_generic enforces on a standalone plot,
            # repeated here because the marks admitted reach this
            # path without going through it. None of them has a log
            # domain wired up: a KDE's density, a triangulation's
            # coordinates and a barb field's positions all reach the
            # frame through _data_extent only, and silently drawing them
            # against a log axis built from a co-layer would put every
            # one of their points somewhere it does not belong.
            raise Error(
                "render_layers(): Plot.scale_x_log()/scale_y_log() apply only"
                " to Mark.POINT/LINE/AREA/EFFECT_SCATTER, the same rule a"
                " standalone render enforces -- layer "
                + String(i)
                + " is "
                + plots[i]._mark.name()
                + ", whose domain is only ever taken linearly"
            )
        if plots[i]._secondary_axis and plots[i]._mark == Mark.RUG:
            raise Error(
                "render_layers(): Plot.secondary_axis() has nothing to do on a"
                " Mark.RUG layer (layer "
                + String(i)
                + ") -- a rug has no y dimension, so it would contribute"
                " nothing to the secondary domain and the right-hand axis"
                " would silently not be drawn at all"
            )
        # Explicit domains are taken when every layer that sets one
        # agrees, and become the shared domain in place of the combined
        # data extent (#434). That is what an overlay means: a layer
        # with no override scales against the same numbers. Two layers
        # asking for different axes have no shared frame, and say so.
        # Color domains are per-layer, not merged: each layer draws its
        # own mark with its own colors, and only one layer in an overlay
        # normally carries a continuous color channel at all.
        _validate_color_domain(plots[i])
        if plots[i]._x_domain.has:
            _validate_domain_override(
                plots[i]._x_domain, plots[i]._x_log, "Plot.scale_x_domain"
            )
            _merge_override(
                x_override, plots[i]._x_domain, i, "Plot.scale_x_domain"
            )
        if plots[i]._y_domain.has:
            if plots[i]._secondary_axis:
                raise Error(
                    "render_layers(): Plot.scale_y_domain() on a"
                    " .secondary_axis() layer isn't supported yet -- layer "
                    + String(i)
                )
            _validate_domain_override(
                plots[i]._y_domain, plots[i]._y_log, "Plot.scale_y_domain"
            )
            _merge_override(
                y_override, plots[i]._y_domain, i, "Plot.scale_y_domain"
            )
        if not x_log_seen:
            x_log_seen = True
            x_log_value = plots[i]._x_log
        elif plots[i]._x_log != x_log_value:
            raise Error(
                "render_layers(): every layer must agree on"
                " Plot.scale_x_log() -- got a mix of log and linear x-axes"
                " (layer "
                + String(i)
                + ")"
            )
        if plots[i]._secondary_axis:
            if not y2_log_seen:
                y2_log_seen = True
                y2_log_value = plots[i]._y_log
            elif plots[i]._y_log != y2_log_value:
                raise Error(
                    "render_layers(): every Plot.secondary_axis() layer must"
                    " agree on Plot.scale_y_log() -- got a mix of log and"
                    " linear secondary y-axes (layer "
                    + String(i)
                    + ")"
                )
        else:
            if not y_log_seen:
                y_log_seen = True
                y_log_value = plots[i]._y_log
            elif plots[i]._y_log != y_log_value:
                raise Error(
                    "render_layers(): every primary-axis layer must agree on"
                    " Plot.scale_y_log() -- got a mix of log and linear"
                    " y-axes (layer "
                    + String(i)
                    + ")"
                )
        if plots[i]._y_log and (
            plots[i]._mark == Mark.AREA or plots[i]._mark == Mark.HISTOGRAM
        ):
            raise Error(
                "render_layers(): Plot.scale_y_log() isn't supported on a"
                " Mark.AREA/HISTOGRAM layer -- its y-domain is always forced"
                " through a"
                " zero baseline, and zero has no logarithm (layer "
                + String(i)
                + ")"
            )
        _validate_continuous_encoding(
            plots[i], "render_layers(): layer " + String(i)
        )
        _validate_log_scale_annotations(plots[i])
        # Last in the loop so the layering-specific rejections above are
        # what a caller meets first; this is where a layer's own
        # encode-time checks (column lengths, level counts) run.
        domains.append(_layer_domain(plots[i]))

    var has_secondary = False
    var has_primary = False
    for i in range(len(plots)):
        if plots[i]._secondary_axis:
            has_secondary = True
        else:
            has_primary = True
    if has_secondary and not has_primary:
        raise Error(
            "render_layers(): at least one layer must stay on the primary"
            " y-axis (every layer calling .secondary_axis() leaves nothing for"
            ' "secondary" to mean relative to)'
        )

    var theme = plots[0]._theme

    # Every layer's columns, already read out of whichever field its mark
    # keeps them in and already widened for y_err (see `_LayerDomain`).
    var combined_x = List[Float64]()
    var combined_y = List[Float64]()
    var combined_y2 = List[Float64]()
    var any_zero_baseline = False
    var any_zero_baseline2 = False
    # Every primary layer an ECDF: the y-axis is a proportion whose two
    # ends mean "none of the sample" and "all of it", so it is pinned to
    # exactly [0, 1] as _render_ecdf pins it, rather than padded to
    # 1.05. Any other mark in the group and the axis is data again.
    var all_ecdf = True
    for i in range(len(plots)):
        for v in domains[i].xs:
            combined_x.append(v)
        if plots[i]._secondary_axis:
            for v in domains[i].ys:
                combined_y2.append(v)
            if domains[i].zero_baseline:
                any_zero_baseline2 = True
        else:
            for v in domains[i].ys:
                combined_y.append(v)
            if domains[i].zero_baseline:
                any_zero_baseline = True
            if not (plots[i]._mark == Mark.ECDF):
                all_ecdf = False

    if len(combined_x) == 0:
        return _RenderResult(text_requests^, ox0, oy0, ox1, oy1)

    # Scaled by the shared (plots[0]) theme.scale; see _Scaled.
    var sc = _Scaled(theme)

    # Both domains span every primary-axis layer's data. A Mark.AREA or
    # Mark.KDE layer anywhere in a group forces the zero baseline for that
    # group's axis (already checked above to be incompatible with that
    # group being log). y_log_value/x_log_value default to False when no
    # layer set them (y_log_seen/x_log_seen stay False only when plots is
    # empty, already returned above).
    #
    # `has_y_data` is false only when every primary-axis layer is a
    # Mark.RUG -- a stack of nothing but observation ticks. There is no
    # host y-axis for the rugs to ride, so the frame falls back to what
    # a standalone rugplot() draws: the LinearScale(0, 1) placeholder
    # _draw_continuous_axis_frame requires, with the y half suppressed
    # Drawing it would caption the chart "0.0 0.2 ... 1.0", a
    # density that isn't there. The x-axis and vertical gridlines stay:
    # the observation's value is the one thing a rug does encode.
    var has_y_data = len(combined_y) > 0
    var y_scale = LinearScale(0.0, 1.0, 0.0, 1.0)
    if has_y_data:
        # An explicit scale_y_domain() wins over the ECDF pin: the caller
        # asked for that axis. Otherwise a group of nothing but ECDFs is
        # pinned to [0, 1], and any other group is sized from its data.
        y_scale = _domain_override_scale(
            y_override, y_log_value
        ) if y_override.has else (
            LinearScale(0.0, 1.0, 0.0, 1.0) if all_ecdf else (
                _log_data_extent(combined_y) if y_log_value else (
                    _zero_baseline_y_extent(
                        combined_y
                    ) if any_zero_baseline else _data_extent(combined_y)
                )
            )
        )
    var x_scale = _domain_override_scale(
        x_override, x_log_value
    ) if x_override.has else (
        _log_data_extent(combined_x) if x_log_value else _data_extent(
            combined_x
        )
    )
    # A time axis rides along on the combined domain, which is already in
    # POSIX seconds: overlaying two series recorded in different zones is
    # legitimate (the instants are absolute), and the axis then reads in
    # the first layer's zone, the same rule a standalone plot follows.
    for i in range(len(plots)):
        if plots[i]._x_time:
            x_scale.is_time = True
            x_scale.tz_offset = plots[i]._x_tz_offset
            break

    var has_secondary_data = has_secondary and len(combined_y2) > 0
    var y_scale2 = LinearScale(0.0, 0.0, 0.0, 1.0)
    if has_secondary_data:
        y_scale2 = _log_data_extent(combined_y2) if y2_log_value else (
            _zero_baseline_y_extent(
                combined_y2
            ) if any_zero_baseline2 else _data_extent(combined_y2)
        )

    # secondary_axis_reserve is sized the way _draw_continuous_axis_frame
    # sizes the left margin: measure the secondary domain's tick labels,
    # then add tick_length + label_gap + margin_buffer. 0 with no secondary
    # axis. The render's shared `cache` serves every measurement here (the
    # secondary axis, then one legend section per layer) and the labels
    # drawn afterwards.

    var secondary_axis_reserve = 0
    if has_secondary_data:
        var y2_ticks_for_margin = y_scale2.ticks()
        var y2_labels_for_margin = y2_ticks_for_margin.labels(
            theme.y_tick_format
        )
        secondary_axis_reserve = (
            Int(
                _max_label_width(
                    y2_labels_for_margin, sc.font_size, cache=cache
                )
            )
            + sc.tick_length
            + sc.label_gap
            + sc.margin_buffer
        )

    # one legend row per named layer (Plot.series_name()), in that
    # layer's own Theme.mark_color -- a secondary-axis layer's row is
    # suffixed so the reader knows which axis it reads against. Collected
    # once here and reused both for legend_reserve's width measurement
    # and the actual draw below.
    var series_names = List[String]()
    var series_colors = List[Color]()
    for j in range(len(plots)):
        if plots[j]._labels.series_name.byte_length() > 0:
            var name = plots[j]._labels.series_name
            if plots[j]._secondary_axis:
                name += " (right axis)"
            series_names.append(name)
            series_colors.append(plots[j]._theme.mark_color)

    # legend_reserve is the widest legend section across every
    # encoding-using Mark.POINT layer, each measured with that layer's own
    # _Scaled; sections stack vertically, so the column width is a max,
    # not a sum.
    var legend_width = 0
    for j in range(len(plots)):
        var p_sc_j = _Scaled(plots[j]._theme)
        var ch_j = _PointChannels(plots[j], p_sc_j)
        var layer_legend = _legend_reserve_for(
            plots[j], ch_j, p_sc_j, cache=cache
        )
        legend_width = max(legend_width, layer_legend.left + layer_legend.right)
    if len(series_names) > 0:
        legend_width = max(
            legend_width,
            _dynamic_legend_width(
                series_names, sc.legend_swatch_size, sc, cache=cache
            ),
        )

    # A column on one side or the other, never a row: a layered chart
    # stacks a per-layer point legend under the series legend, and the
    # point legend's continuous sections are vertical (see
    # `_legend_reserve_for`). LegendPosition.TOP/BOTTOM therefore fall
    # back to RIGHT here, as Theme.legend_position documents.
    var legend_reserve = _LegendLayout()
    if legend_width > 0:
        legend_reserve.active = True
        if theme.legend_position == LegendPosition.LEFT:
            legend_reserve.position = LegendPosition.LEFT
            legend_reserve.left = legend_width
        else:
            legend_reserve.right = legend_width

    var frame = _draw_continuous_axis_frame(
        target,
        x_scale,
        y_scale,
        theme,
        _with_secondary_axis(legend_reserve, secondary_axis_reserve),
        ox0,
        oy0,
        ox1,
        oy1,
        y_axis_visible=has_y_data,
        cache=cache,
    )
    _extend_text_requests(text_requests, frame.text_requests)

    # The secondary axis line/ticks/labels at the plot rect's right edge
    # (frame.px1), the mirror of the primary axis at frame.px0: ticks point
    # right, labels sit left-aligned past them. No gridlines.
    var out_y_scale2 = y_scale2
    out_y_scale2.range_min = Float64(frame.py1)
    out_y_scale2.range_max = Float64(frame.py0)
    if has_secondary_data:
        var y2_ticks = out_y_scale2.ticks()
        var y2_labels = y2_ticks.labels(theme.y_tick_format)
        var y2_label_baseline_offset = Int(sc.font_size * 0.35)
        target.draw_line_aa(
            frame.px1,
            frame.py0,
            frame.px1,
            frame.py1,
            theme.axis_color,
            width=sc.scale,
        )
        for i in range(len(y2_ticks.values)):
            var py = _axis_pixel(out_y_scale2, y2_ticks.values[i])
            target.draw_line_aa(
                frame.px1,
                py,
                frame.px1 + sc.tick_length,
                py,
                theme.axis_color,
                width=sc.scale,
            )
            text_requests.append(
                _TextRequest(
                    frame.px1 + sc.tick_length + sc.label_gap,
                    py + y2_label_baseline_offset,
                    y2_labels[i],
                    theme.text_color,
                    sc.font_size,
                    TextAlign.LEFT,
                    theme.font_family,
                )
            )

    # The legend column's x is shared (past the secondary axis's reserve
    # when there is one); legend_y is a running cursor threaded through
    # each layer's section(s).
    var legend_x = frame.px1 + secondary_axis_reserve + sc.margin_right
    var legend_y = frame.py0
    if len(series_names) > 0:
        _draw_legend(
            target,
            text_requests,
            series_names,
            series_colors,
            legend_x,
            legend_y,
            theme,
        )
        legend_y += len(series_names) * (
            sc.legend_swatch_size + sc.legend_row_gap
        )
    # Every branch here hands the shared `frame.x_scale`/`layer_y_scale`
    # to the same `_draw_*_layer` the mark's own `_render_*` calls, never
    # to a second copy of its geometry -- the mistake
    # `_render_bar_combo_layers` made, which silently dropped `step=`
    # then `dashes=`, and still drops
    # `mark_point(tooltips=True)` today.
    #
    # `layer_sc` is the layer's own `_Scaled`, not the frame's: the frame
    # belongs to plots[0], while `line_width`, `point_radius` and
    # `tick_length` follow each layer's own `Theme.scale`, as
    # render_layers() documents.
    # Filled annotations under every layer's marks (#501), against the
    # same per-layer result the annotation pass after the marks builds.
    for j in range(len(plots)):
        var under_y_scale = out_y_scale2 if plots[
            j
        ]._secondary_axis else frame.y_scale
        var under_has_y = has_secondary_data if plots[
            j
        ]._secondary_axis else frame.has_y_scale
        var under_result = _RenderResult(
            List[_TextRequest](),
            frame.px0,
            frame.py0,
            frame.px1,
            frame.py1,
            under_y_scale,
            under_has_y,
            frame.x_scale,
            True,
        )
        var under_areas = _draw_annotation_areas(
            target, plots[j], under_result, plots[j]._theme
        )
        for k in range(len(under_areas)):
            text_requests.append(under_areas[k].copy())
        var under_bands = _draw_annotation_bands(
            target, plots[j], under_result, plots[j]._theme
        )
        for k in range(len(under_bands)):
            text_requests.append(under_bands[k].copy())

    for j in range(len(plots)):
        var mark = plots[j]._mark
        var layer_theme = plots[j]._theme
        var layer_sc = _Scaled(layer_theme)
        var layer_y_scale = out_y_scale2 if plots[
            j
        ]._secondary_axis else frame.y_scale
        if mark == Mark.POINT or mark == Mark.EFFECT_SCATTER:
            if len(plots[j].x_data) == 0:
                continue
            var ch_j = _PointChannels(plots[j], layer_sc)
            legend_y = _draw_point_layer(
                target,
                text_requests,
                plots[j],
                ch_j,
                frame.x_scale,
                layer_y_scale,
                legend_x,
                legend_y,
                draw_halo=mark == Mark.EFFECT_SCATTER,
            )
        elif mark == Mark.LINE:
            if len(plots[j].x_data) == 0:
                continue
            _draw_line_layer(target, plots[j], frame.x_scale, layer_y_scale)
        elif mark == Mark.AREA:
            if len(plots[j].x_data) == 0:
                continue
            _draw_area_layer(target, plots[j], frame.x_scale, layer_y_scale)
        elif mark == Mark.HISTOGRAM:
            if len(plots[j].x_data) == 0:
                continue
            _draw_histogram_layer(
                target, plots[j], frame.x_scale, layer_y_scale
            )
        elif mark == Mark.KDE:
            # domains[j].xs/ys are the density curve `_layer_domain`
            # already evaluated for the combined domain, passed straight
            # through so the geometry drawn is the geometry the axis was
            # sized for. The observations are re-read only for the
            # mark_kde(rug=True) ticks.
            _draw_kde_layer(
                target,
                plots[j],
                domains[j].xs,
                domains[j].ys,
                _kde_observations(plots[j]),
                frame.x_scale,
                layer_y_scale,
                layer_sc,
                Float64(frame.py1),
            )
        elif mark == Mark.ECDF:
            _draw_ecdf_layer(
                target,
                plots[j],
                domains[j].xs,
                domains[j].ys,
                frame.x_scale,
                layer_y_scale,
                layer_sc,
            )
        elif mark == Mark.RUG:
            # A rug rides the frame's baseline, not `layer_y_scale`: its
            # ticks are all the same length and all sit on the plot
            # rect's bottom edge, which is the whole of what a rug says.
            # In a stack the y-axis is the host layer's and the rug is a
            # passenger on it.
            _draw_rug_ticks(
                target,
                domains[j].xs,
                frame.x_scale,
                Float64(frame.py1),
                layer_sc,
                layer_theme.mark_color,
            )
        elif mark == Mark.BARBS:
            _draw_barbs_layer(
                target, plots[j], frame.x_scale, layer_y_scale, layer_sc
            )
        elif mark == Mark.TRICONTOUR:
            _draw_tricontour_layer(
                target, plots[j], frame.x_scale, layer_y_scale, layer_sc
            )
        elif mark == Mark.TRICONTOURF:
            _draw_tricontourf_layer(
                target, plots[j], frame.x_scale, layer_y_scale
            )
        elif mark == Mark.TRIPLOT:
            _draw_triplot_layer(
                target, plots[j], frame.x_scale, layer_y_scale, layer_sc
            )
        elif mark == Mark.TRIPCOLOR:
            _draw_tripcolor_layer(
                target, plots[j], frame.x_scale, layer_y_scale, layer_sc
            )

    # Each layer's annotate_*() draws last, against that layer's own
    # y_scale (primary or secondary) and the one shared x_scale (there is
    # no secondary x-axis). A throwaway _RenderResult per layer, built from
    # the shared rect plus that layer's y_scale and the frame's x_scale, is
    # enough to reuse every annotation function unmodified -- same order a
    # standalone render uses (areas and bands underneath, then lines/
    # vlines, points on top, best_fit last).
    for j in range(len(plots)):
        var layer_y_scale = out_y_scale2 if plots[
            j
        ]._secondary_axis else frame.y_scale
        # Whether that y-scale measures anything. A secondary-axis
        # layer's does when some layer contributed to the secondary
        # domain; a primary one's follows the frame, which is false only
        # for the all-Mark.RUG stack whose y half was suppressed above.
        # Either way this is the same fact `_ContinuousFrame.result()`
        # publishes, so annotate_line()/annotate_area() raise here for
        # exactly the reason they raise on a standalone rug rather than
        # drawing against a placeholder domain.
        var layer_has_y_scale = has_secondary_data if plots[
            j
        ]._secondary_axis else frame.has_y_scale
        var layer_result = _RenderResult(
            List[_TextRequest](),
            frame.px0,
            frame.py0,
            frame.px1,
            frame.py1,
            layer_y_scale,
            layer_has_y_scale,
            frame.x_scale,
            True,
        )
        # Areas and bands were drawn under the marks above (#501).
        var layer_area_requests = List[_TextRequest]()
        var layer_band_requests = List[_TextRequest]()
        var layer_vline_requests = _draw_annotation_vlines(
            target, plots[j], layer_result, plots[j]._theme
        )
        var layer_line_requests = _draw_annotation_lines(
            target, plots[j], layer_result, plots[j]._theme
        )
        var layer_point_requests = _draw_annotation_points(
            target, plots[j], layer_result, plots[j]._theme
        )
        var layer_best_fit_requests = _draw_annotation_best_fit(
            target, plots[j], layer_result, plots[j]._theme
        )
        _extend_text_requests(text_requests, layer_area_requests)
        _extend_text_requests(text_requests, layer_band_requests)
        _extend_text_requests(text_requests, layer_vline_requests)
        _extend_text_requests(text_requests, layer_line_requests)
        _extend_text_requests(text_requests, layer_point_requests)
        _extend_text_requests(text_requests, layer_best_fit_requests)

    return _RenderResult(
        text_requests^, frame.px0, frame.py0, frame.px1, frame.py1
    )
