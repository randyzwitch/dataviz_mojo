"""Text: the deferred-draw mechanism every chart's labels go through,
and the theme-derived sizes they are measured in.

Split out of `plot.mojo` (#222). `DrawTarget` deliberately has no
`draw_text` -- raster text needs `canvas.text`'s FreeType/fontconfig
machinery and SVG text needs markup -- so the generic rendering pass
collects `_TextRequest`s instead of drawing, and each entry point
replays them afterward through the backend it actually has. That is
also what keeps a label from being painted over by a later mark.

`_Scaled` lives here because it is what text is measured against:
`Theme.scale` applied once to every size and gap in a chart.
"""

from std.math import pi

from canvas.buffer import Canvas
from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.text.render import FontWeight, TextAlign, draw_text, measure_text
from canvas.vector.draw_target import DrawTarget
from canvas.vector.svg import SvgCanvas

from dataviz.continuous import area, line
from dataviz.facets import render_facets
from dataviz.layers import render_layers
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _render_generic,
    _render_into,
    _render_svg_into,
    render,
    render_svg,
)
from dataviz.theme import Theme


struct _Scaled(Movable):
    """Every pixel-sized quantity the render paths draw with, pre-multiplied
    by `theme.scale` in one place (see `Theme.scale`). Built fresh from a
    Theme at the top of each render function; a handful of multiplies,
    not cached.

    `scale` itself is the raw multiplier, for the one place that needs the
    bare factor: every axis line/gridline/tick mark is drawn
    `width=sc.scale` pixels wide, since those strokes have no `Theme`
    width field of their own and would otherwise stay 1 pixel wide at any
    `scale`.
    """

    var scale: Float64
    var font_size: Float64
    var point_radius: Float64
    var line_width: Float64
    var size_range_min: Float64
    var size_range_max: Float64
    var margin_left: Int
    var margin_right: Int
    var margin_top: Int
    var margin_bottom: Int
    var tick_length: Int
    var label_gap: Int
    var legend_width: Int
    var legend_swatch_size: Int
    var legend_row_gap: Int
    var margin_buffer: Int
    var title_font_size: Float64
    var subtitle_font_size: Float64
    var axis_title_font_size: Float64
    var continuous_legend_bar_width: Int
    var continuous_legend_bar_height: Int
    var error_bar_cap_width: Float64

    def __init__(out self, theme: Theme):
        var s = theme.scale
        self.scale = s
        self.font_size = theme.font_size * s
        self.point_radius = theme.point_radius * s
        self.line_width = theme.line_width * s
        self.size_range_min = theme.size_range_min * s
        self.size_range_max = theme.size_range_max * s
        self.margin_left = Int(Float64(theme.margin_left) * s)
        self.margin_right = Int(Float64(theme.margin_right) * s)
        self.margin_top = Int(Float64(theme.margin_top) * s)
        self.margin_bottom = Int(Float64(theme.margin_bottom) * s)
        self.tick_length = Int(Float64(theme.tick_length) * s)
        self.label_gap = Int(Float64(theme.label_gap) * s)
        self.legend_width = Int(Float64(theme.legend_width) * s)
        self.legend_swatch_size = Int(Float64(theme.legend_swatch_size) * s)
        self.legend_row_gap = Int(Float64(theme.legend_row_gap) * s)
        self.margin_buffer = Int(Float64(theme.margin_buffer) * s)
        self.title_font_size = theme.title_font_size * s
        self.subtitle_font_size = theme.subtitle_font_size * s
        self.axis_title_font_size = theme.axis_title_font_size * s
        self.continuous_legend_bar_width = Int(
            Float64(theme.continuous_legend_bar_width) * s
        )
        self.continuous_legend_bar_height = Int(
            Float64(theme.continuous_legend_bar_height) * s
        )
        self.error_bar_cap_width = theme.error_bar_cap_width * s


def _max_label_width(
    labels: List[String], font_size: Float64, *, mut cache: FontCache
) raises -> Float64:
    """The widest rendered ink width among `labels` at `font_size`, used to
    size the left margin to the y-axis tick labels before the plot area's
    pixel range is finalized (tick values depend only on the data domain,
    so measuring early is exact).

    Measures through the caller's `cache`, the one `FontCache` a render
    shares between every measurement and every label it draws (#255,
    `FontCache`): a fresh cache re-pays the font scan, font
    resolution and TTF parsing (0.44ms for a 5-label call against
    0.056ms warm), which is why there is no overload without one.
    """
    var max_width = 0.0
    for label in labels:
        var m = measure_text(label, font_size, cache=cache)
        if m.width > max_width:
            max_width = m.width
    return max_width


struct _TextRequest(Copyable, Movable):
    """One deferred `draw_text()` call, collected while the
    `DrawTarget`-generic rendering pass runs (`DrawTarget` has no
    `draw_text`). `render()`/`render_svg()` each replay the list their own
    way afterward, via `canvas.text.draw_text` or `SvgCanvas.draw_text`.

    `family` is baked in at construction from whichever `Theme` built the
    request, since `render_facets()`/`render_layers()` combine several
    independently themed `Plot`s into one draw pass (see
    `Theme.font_family`). `bold` defaults to `False` everywhere except
    `_label_text_requests`'s chart title.
    """

    var x: Int
    var y: Int
    var text: String
    var color: Color
    var size: Float64
    var align: TextAlign
    var family: String
    var bold: Bool
    var rotation: Float64

    def __init__(
        out self,
        x: Int,
        y: Int,
        text: String,
        color: Color,
        size: Float64,
        align: TextAlign,
        family: String,
        bold: Bool = False,
        rotation: Float64 = 0.0,
    ):
        self.x = x
        self.y = y
        self.text = text
        self.color = color
        self.size = size
        self.align = align
        self.family = family
        self.bold = bold
        self.rotation = rotation


def _text_advance(text: String, sc: _Scaled) -> Int:
    """A rough width for `text` at `sc.font_size`, for laying one legend
    section next to the next without measuring.

    Deliberately an estimate: these are the two-or-three short numeric
    labels a continuous legend carries, the sections are separated by
    `label_gap` anyway, and measuring here would mean threading the
    render's font cache through purely to place a gap. Over-estimating
    is the safe direction, so this uses a generous per-character width.

    Args:
        text: The label.
        sc: The render's scaled layout metrics.

    Returns:
        An approximate advance width in pixels.
    """
    return Int(Float64(text.byte_length()) * sc.font_size * 0.62)


struct _LabelsFrame(Movable):
    """`_apply_labels`'s result: the outer rect `render()`/`render_svg()`
    hand to `_render_generic`, shrunk to make room for `Plot.labels()`'s
    titles. `_apply_labels` builds no `_TextRequest`s;
    `_label_text_requests` does that after rendering.
    """

    var ox0: Int
    var oy0: Int
    var ox1: Int
    var oy1: Int

    def __init__(out self, ox0: Int, oy0: Int, ox1: Int, oy1: Int):
        self.ox0 = ox0
        self.oy0 = oy0
        self.ox1 = ox1
        self.oy1 = oy1


def _apply_labels(
    plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int
) raises -> _LabelsFrame:
    """Reserve margin space for `Plot.labels()`'s chart/axis titles, given
    the original outer bounds. Called by `_render_into`/
    `_render_svg_into` (and the facet/layer variants) before
    `_render_generic`; the mark-specific code stays unaware titles exist,
    since shrinking the rect up front has the same effect as threading
    title state through every function.

    Only reserves margin. A title's along-axis position depends only on
    this reservation, but its cross-axis centering should track the real
    inner plot rect (dynamic left margin, legend column), which isn't
    known until `_render_generic` returns; `_label_text_requests` builds
    the text afterward using `_RenderResult`'s rect.

    `Mark.ARC` has no axes, so `x_title`/`y_title` raise on an `ARC`
    plot; `title` works for any mark.
    """
    if (
        plot._labels.x_title.byte_length() > 0
        or plot._labels.y_title.byte_length() > 0
    ) and plot._mark == Mark.ARC:
        raise Error(
            "Plot.labels(): x_title/y_title don't apply to Mark.ARC (it"
            " has no x/y axes to caption) -- only title applies to a"
            " pie/donut chart"
        )

    var sc = _Scaled(plot._theme)
    var extra_top = (
        Int(sc.title_font_size)
        + sc.label_gap if plot._labels.title.byte_length()
        > 0 else 0
    )
    extra_top += (
        Int(sc.subtitle_font_size)
        + sc.label_gap if plot._labels.subtitle.byte_length()
        > 0 else 0
    )
    var extra_bottom = (
        Int(sc.axis_title_font_size)
        + sc.label_gap if plot._labels.x_title.byte_length()
        > 0 else 0
    )
    var extra_left = (
        Int(sc.axis_title_font_size)
        + sc.label_gap if plot._labels.y_title.byte_length()
        > 0 else 0
    )

    return _LabelsFrame(
        ox0 + extra_left, oy0 + extra_top, ox1, oy1 - extra_bottom
    )


def _label_text_requests(
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    px0: Int,
    py0: Int,
    px1: Int,
    py1: Int,
) raises -> List[_TextRequest]:
    """Build `Plot.labels()`'s title/subtitle/x_title/y_title
    `_TextRequest`s after `_render_generic` returns. Each title's
    along-axis position (distance from the top/bottom/left edge) is
    relative to the original outer bounds `ox0`..`oy1`; its cross-axis
    centering uses the actual inner plot rect `px0`..`py1` from
    `_RenderResult`.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var text_requests = List[_TextRequest]()

    if plot._labels.title.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                (px0 + px1) // 2,
                oy0 + Int(sc.title_font_size * 0.8),
                plot._labels.title,
                theme.text_color,
                sc.title_font_size,
                TextAlign.CENTER,
                theme.font_family,
                bold=theme.title_bold,
            )
        )

    if plot._labels.subtitle.byte_length() > 0:
        # Stacks directly below the title's reserved band, which is 0 when
        # there is no title, so a lone subtitle draws at the very top.
        var title_band = (
            Int(sc.title_font_size)
            + sc.label_gap if plot._labels.title.byte_length()
            > 0 else 0
        )
        text_requests.append(
            _TextRequest(
                (px0 + px1) // 2,
                oy0 + title_band + Int(sc.subtitle_font_size * 0.8),
                plot._labels.subtitle,
                theme.subtitle_color,
                sc.subtitle_font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    if plot._labels.x_title.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                (px0 + px1) // 2,
                oy1 - Int(sc.axis_title_font_size * 0.25),
                plot._labels.x_title,
                theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
                theme.font_family,
            )
        )

    if plot._labels.y_title.byte_length() > 0:
        text_requests.append(
            _TextRequest(
                ox0 + Int(sc.axis_title_font_size * 0.8),
                (py0 + py1) // 2,
                plot._labels.y_title,
                theme.text_color,
                sc.axis_title_font_size,
                TextAlign.CENTER,
                theme.font_family,
                rotation=-pi / 2.0,
            )
        )

    return text_requests^


def _replay_text_requests(
    mut canvas: Canvas, requests: List[_TextRequest], mut cache: FontCache
) raises:
    """Draw every `_TextRequest` in `requests` into `canvas` via
    `canvas.text.draw_text`, the raster half of replaying the deferred
    labels. Shared by every raster entry point.
    """
    for req in requests:
        draw_text(
            canvas,
            req.x,
            req.y,
            req.text,
            req.color,
            req.size,
            align=req.align,
            family=req.family,
            weight=FontWeight.BOLD if req.bold else FontWeight.NORMAL,
            rotation=req.rotation,
            cache=cache,
        )


def _replay_text_requests_svg(
    mut svg: SvgCanvas, requests: List[_TextRequest]
) raises:
    """`_replay_text_requests`' counterpart for `SvgCanvas`, via
    `SvgCanvas.draw_text`. A separate function because `DrawTarget` has
    no `draw_text` to dispatch through.
    """
    for req in requests:
        svg.draw_text(
            req.x,
            req.y,
            req.text,
            req.color,
            req.size,
            req.align,
            family=req.family,
            weight=FontWeight.BOLD if req.bold else FontWeight.NORMAL,
            rotation=req.rotation,
        )


def _extend_text_requests(mut dst: List[_TextRequest], src: List[_TextRequest]):
    """Append a copy of every `_TextRequest` in `src` onto `dst`; used by
    the facet/layer renders to gather per-cell/per-layer labels into one
    list.
    """
    for req in src:
        dst.append(req.copy())
