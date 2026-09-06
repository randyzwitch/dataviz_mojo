"""`render_layers()`: several plots sharing one frame.

Split out of `plot.mojo` (#222). Layering is not just drawing twice --
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
from dataviz.continuous import (
    _PointChannels,
    _build_line_path,
    _draw_area_layer,
    _draw_line_layer,
    _draw_point_layer,
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
from dataviz.validate import (
    _check_line_smoothing,
    _validate_categorical_encoding,
    _validate_continuous_encoding,
)


def save_layers(plots: List[Plot], path: String) raises:
    """`save()`'s `render_layers()`/`render_layers_svg()` counterpart. The
    format comes from `plots[0]`'s theme when the path's extension
    doesn't decide it. Raises on an empty `plots`.

    SVG output writes accessible markup automatically (#212) from
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

    Restricted to `Mark.POINT`/`LINE`/`AREA`, plus at most one `Mark.BAR`
    layer for a bar-plus-line combo chart (dispatched to
    `_render_bar_combo_layers`, which has a narrower scope). A
    `Plot.secondary_axis()` layer scales against its own y-domain on the
    right edge. A `Mark.POINT` layer may use `color`/`color_categories`/
    `size` encoding with its own scales and legend section; sections
    stack in one column in layer order. There is no per-series legend
    for flat-colored layers.

    Shared chrome (background, gridlines, axis colors, margins, font
    size, `Plot.labels()` titles) comes from `plots[0]`; every other
    layer's `Theme` governs only its own mark (`mark_color`,
    `point_radius`, `line_width`, `line_smoothing`, scaled by its own
    `Theme.scale`). A secondary-axis layer's `y_title` captions the right
    axis.

    Every `Plot` must share the same `.size()`; an empty list raises.
    Supersampled by `plots[0]._theme.raster_supersample` like `render()`,
    bumping every layer's scale together on a copy (`plots` is a plain
    borrow, #208).
    """
    _require_uniform_size(plots, "render_layers")
    var factor = plots[0]._theme.raster_supersample
    _require_positive_supersample(factor, "render_layers")
    var canvas = Canvas(plots[0].width * factor, plots[0].height * factor)
    # The half-pixel that box-downsampling costs: downsample() averages
    # the device block f*p .. f*p+f-1 into output pixel p, whose centre
    # sits at user coordinate p + (f-1)/(2f). Scaling alone therefore
    # lands everything (f-1)/(2f) px early -- 0.25 at factor 2, 0.333 at
    # 3, 0.375 at 4 -- so the origin shifts by (f-1)/2 device px first.
    canvas.translate(Float64(factor - 1) / 2.0, Float64(factor - 1) / 2.0)
    canvas.scale(Float64(factor), Float64(factor))
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
    return downsample(canvas, factor)


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

    # The bar layer's own y_err/y_err_lower/y_err_upper (#216, allowed here
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

    # #215: one legend row per named layer (Plot.series_name()), the bar
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
        var px = List[Float64](capacity=len(plots[i].y_data))
        var py = List[Float64](capacity=len(plots[i].y_data))
        for k in range(len(plots[i].y_data)):
            px.append(frame.x_scale.center(k))
            py.append(frame.y_scale.to_pixel(plots[i].y_data[k]))
        if plots[i]._mark == Mark.POINT:
            for k in range(len(px)):
                target.fill_circle_aa(
                    px[k],
                    py[k],
                    Float64(round_to_int(layer_sc.point_radius)),
                    layer_theme.mark_color,
                )
        elif plots[i]._mark == Mark.LINE:
            var path = _build_line_path(px, py, layer_theme.line_smoothing)
            target.stroke_path_aa(
                path, layer_theme.mark_color, width=layer_sc.line_width
            )
        else:
            # Mark.AREA -- same closed-down-to-baseline technique
            # _draw_area_layer uses, just against this frame's
            # categorical x positions instead of a continuous x_scale.
            var baseline_py = frame.y_scale.to_pixel(0.0)
            if round_to_int(baseline_py) == round_to_int(
                frame.y_scale.range_min
            ):
                baseline_py -= 1.0
            var path = _build_line_path(px, py, layer_theme.line_smoothing)
            path.line_to(px[len(px) - 1], baseline_py)
            path.line_to(px[0], baseline_py)
            path.close()
            target.fill_path_aa(
                path, layer_theme.mark_color, fill_rule=FillRule.NONZERO
            )

    return frame.result()


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
    `_render_generic` uses (`_draw_continuous_axis_frame`,
    `_draw_point_layer`/`_draw_line_layer`/`_draw_area_layer`). What
    differs: domains computed across every layer's data, a legend column
    sized across every layer with a legend-y cursor threaded through in
    order, and an optional secondary axis. Exactly one `Mark.BAR` layer
    dispatches to `_render_bar_combo_layers` first.

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

    # Log-ness (#217) is decided per axis -- x is shared by every layer
    # (there is no secondary x-axis), while y splits into the primary
    # group and the Plot.secondary_axis() group, each independently. Every
    # layer sharing an axis must agree; the first layer on each axis sets
    # that axis's value and every later one is checked against it, so the
    # raised message names the first layer that disagrees.
    var x_log_seen = False
    var x_log_value = False
    var y_log_seen = False
    var y_log_value = False
    var y2_log_seen = False
    var y2_log_value = False
    for i in range(len(plots)):
        # Layering-specific check: a standalone Mark.BAR is legal, a layered
        # one alongside these isn't. A lone Mark.BAR already dispatched above,
        # so this fires only for Mark.ARC and other unsupported marks.
        if not (
            plots[i]._mark == Mark.POINT
            or plots[i]._mark == Mark.LINE
            or plots[i]._mark == Mark.AREA
        ):
            raise Error(
                "render_layers(): only Mark.POINT/Mark.LINE/Mark.AREA can be"
                " layered here (got a different mark -- Mark.BAR is supported"
                " only as the lone categorical layer in a bar-combo chart, see"
                " _render_bar_combo_layers; Mark.ARC still isn't supported at"
                " all)"
            )
        if plots[i]._x_domain.has or plots[i]._y_domain.has:
            raise Error(
                "render_layers(): Plot.scale_x_domain()/scale_y_domain() aren't"
                " supported here yet (#209) -- layer "
                + String(i)
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
        if plots[i]._y_log and plots[i]._mark == Mark.AREA:
            raise Error(
                "render_layers(): Plot.scale_y_log() isn't supported on a"
                " Mark.AREA layer -- its y-domain is always forced through a"
                " zero baseline, and zero has no logarithm (layer "
                + String(i)
                + ")"
            )
        _validate_continuous_encoding(
            plots[i], "render_layers(): layer " + String(i)
        )
        _validate_log_scale_annotations(plots[i])

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

    var combined_x = List[Float64]()
    var combined_y = List[Float64]()
    var combined_y2 = List[Float64]()
    var any_area = False
    var any_area2 = False
    for i in range(len(plots)):
        for v in plots[i].x_data:
            combined_x.append(v)
        # A layer's y_err/y_err_lower+y_err_upper widens its contribution to
        # the combined domain to each whisker's endpoints, as
        # _render_generic's y_domain_data does for a standalone plot.
        var has_y_err = len(plots[i].y_err_data) > 0
        var has_y_err_lower = len(plots[i].y_err_lower_data) > 0
        if plots[i]._secondary_axis:
            if has_y_err:
                for j in range(len(plots[i].y_data)):
                    combined_y2.append(
                        plots[i].y_data[j] - plots[i].y_err_data[j]
                    )
                    combined_y2.append(
                        plots[i].y_data[j] + plots[i].y_err_data[j]
                    )
            elif has_y_err_lower:
                for j in range(len(plots[i].y_data)):
                    combined_y2.append(
                        plots[i].y_data[j] - plots[i].y_err_lower_data[j]
                    )
                    combined_y2.append(
                        plots[i].y_data[j] + plots[i].y_err_upper_data[j]
                    )
            else:
                for v in plots[i].y_data:
                    combined_y2.append(v)
            if plots[i]._mark == Mark.AREA:
                any_area2 = True
        else:
            if has_y_err:
                for j in range(len(plots[i].y_data)):
                    combined_y.append(
                        plots[i].y_data[j] - plots[i].y_err_data[j]
                    )
                    combined_y.append(
                        plots[i].y_data[j] + plots[i].y_err_data[j]
                    )
            elif has_y_err_lower:
                for j in range(len(plots[i].y_data)):
                    combined_y.append(
                        plots[i].y_data[j] - plots[i].y_err_lower_data[j]
                    )
                    combined_y.append(
                        plots[i].y_data[j] + plots[i].y_err_upper_data[j]
                    )
            else:
                for v in plots[i].y_data:
                    combined_y.append(v)
            if plots[i]._mark == Mark.AREA:
                any_area = True

    if len(combined_x) == 0:
        return _RenderResult(text_requests^, ox0, oy0, ox1, oy1)

    # Scaled by the shared (plots[0]) theme.scale; see _Scaled.
    var sc = _Scaled(theme)

    # Both domains span every primary-axis layer's data. A Mark.AREA layer
    # anywhere in a group forces the zero baseline for that group's axis
    # (already checked above to be incompatible with that group being log).
    # y_log_value/x_log_value default to False when no layer set them
    # (y_log_seen/x_log_seen stay False only when plots is empty, already
    # returned above).
    var y_scale = _log_data_extent(combined_y) if y_log_value else (
        _zero_baseline_y_extent(combined_y) if any_area else _data_extent(
            combined_y
        )
    )
    var x_scale = _log_data_extent(combined_x) if x_log_value else _data_extent(
        combined_x
    )

    var has_secondary_data = has_secondary and len(combined_y2) > 0
    var y_scale2 = LinearScale(0.0, 0.0, 0.0, 1.0)
    if has_secondary_data:
        y_scale2 = _log_data_extent(combined_y2) if y2_log_value else (
            _zero_baseline_y_extent(combined_y2) if any_area2 else _data_extent(
                combined_y2
            )
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

    # #215: one legend row per named layer (Plot.series_name()), in that
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
    for j in range(len(plots)):
        if len(plots[j].x_data) == 0:
            continue
        var layer_y_scale = out_y_scale2 if plots[
            j
        ]._secondary_axis else frame.y_scale
        if plots[j]._mark == Mark.POINT:
            var p_sc = _Scaled(plots[j]._theme)
            var ch_j = _PointChannels(plots[j], p_sc)
            legend_y = _draw_point_layer(
                target,
                text_requests,
                plots[j],
                ch_j,
                frame.x_scale,
                layer_y_scale,
                legend_x,
                legend_y,
            )
        elif plots[j]._mark == Mark.LINE:
            _draw_line_layer(target, plots[j], frame.x_scale, layer_y_scale)
        elif plots[j]._mark == Mark.AREA:
            _draw_area_layer(target, plots[j], frame.x_scale, layer_y_scale)

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
        var layer_result = _RenderResult(
            List[_TextRequest](),
            frame.px0,
            frame.py0,
            frame.px1,
            frame.py1,
            layer_y_scale,
            True,
            frame.x_scale,
            True,
        )
        var layer_area_requests = _draw_annotation_areas(
            target, plots[j], layer_result, plots[j]._theme
        )
        var layer_band_requests = _draw_annotation_bands(
            target, plots[j], layer_result, plots[j]._theme
        )
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
