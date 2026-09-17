"""Deferred text drawing and theme-scaled layout metrics."""

from std.math import ceil, pi

from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.text.text_run import TextRun
from dataviz.core.mathtext import (
    _label_requests,
    _label_width,
    _layout_label,
    _needs_math,
    _reserve_height,
)
from canvas.text.render import FontWeight, TextAlign, measure_text
from canvas.vector.draw_target import DrawTarget

from dataviz.basic.continuous import area, line
from dataviz.facets import render_facets
from dataviz.layers import render_layers
from dataviz.core.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _render_generic,
    _render_into,
    _render_svg_into,
    render,
    render_svg,
)
from dataviz.core.theme import Theme


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
    var minor_tick_length: Int
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
        self.minor_tick_length = Int(Float64(theme.minor_tick_length) * s)
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
    labels: List[String],
    font_size: Float64,
    *,
    family: String,
    mut cache: FontCache,
) raises -> Float64:
    """The widest label at `font_size` in `family`, which must be the
    family the labels will draw in.

    It used to measure in canvas's default face whatever the theme
    said (#655). The two coincide for the default theme, so nothing
    showed; a serif or condensed theme got every gutter and legend
    column sized for a face its text was not set in.
    """
    var max_width = 0.0
    for label in labels:
        var w = _label_width(label, font_size, family, False, cache=cache)
        if w > max_width:
            max_width = w
    return max_width


struct _TextRequest(Copyable, Movable):
    """One deferred `draw_text()` call, collected while the
    `DrawTarget`-generic rendering pass runs and drawn afterward by
    `_replay_text_requests`, after every mark and annotation pass, so a
    label is never painted over.

    `family` is baked in at construction from whichever `Theme` built the
    request, since `render_facets()`/`render_layers()` combine several
    independently themed `Plot`s into one draw pass (see
    `Theme.font_family`). `bold` defaults to `False` everywhere except
    `_label_text_requests`'s chart title.

    Three kinds share the struct, told apart by `is_runs()` and
    `is_rule()`: a plain label, which is the original and by far the
    most common; a label of several `TextRun`s, which is a math label
    (#371) and draws through `draw_text_runs` (#664); and a fraction or
    radical rule, a line. One list rather than three because the
    replay walks one ordered list, and a rule belongs between the runs
    above and below it.
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
    var runs: List[TextRun]
    var rule_x2: Int
    var rule_y2: Int
    var rule_thickness: Float64

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
        self.runs = List[TextRun]()
        self.rule_x2 = 0
        self.rule_y2 = 0
        self.rule_thickness = 0.0

    @staticmethod
    def rule(
        x: Int, y: Int, x2: Int, y2: Int, thickness: Float64, color: Color
    ) -> Self:
        """A fraction bar rather than text: a line from `(x, y)` to
        `(x2, y2)`, `thickness` wide, replayed with each backend's
        anti-aliased line rather than its text call (#371).

        A request rather than a separate list because a bar belongs
        between the runs above and below it in the one ordered list
        every replay walks, and because the replays are where the
        backend is known.

        Args:
            x: Start x.
            y: Start y.
            x2: End x.
            y2: End y.
            thickness: Line width in pixels.
            color: Line color.

        Returns:
            The request.
        """
        var req = Self(x, y, "", color, 0.0, TextAlign.LEFT, "")
        req.rule_x2 = x2
        req.rule_y2 = y2
        req.rule_thickness = thickness
        return req^

    @staticmethod
    def of_runs(
        x: Int,
        y: Int,
        var runs: List[TextRun],
        color: Color,
        family: String,
        bold: Bool,
        rotation: Float64,
    ) -> Self:
        """One label made of several runs -- a math label (#371) --
        drawn by each backend's `draw_text_runs`, which on SVG is one
        `<text>` of `<tspan>`s rather than one element per run (#664).

        `(x, y)` is the label's origin and the runs carry their own
        pen shifts and baselines, so the request is `TextAlign.LEFT`:
        the layout that built the runs has already placed them for
        whatever alignment the label asked for.

        Args:
            x: The label's origin x.
            y: The label's baseline y.
            runs: The runs, in reading order.
            color: Text color.
            family: Font family, shared by every run.
            bold: Whether every run draws bold.
            rotation: Radians, clockwise on screen, about the origin.

        Returns:
            The request.
        """
        var req = Self(
            x,
            y,
            "",
            color,
            0.0,
            TextAlign.LEFT,
            family,
            bold=bold,
            rotation=rotation,
        )
        req.runs = runs^
        return req^

    def is_runs(self) -> Bool:
        """Whether this request is a label of several runs."""
        return len(self.runs) > 0

    def is_rule(self) -> Bool:
        """Whether this request is a fraction bar, not text."""
        return self.rule_thickness > 0.0


def _text_advance(
    text: String, sc: _Scaled, *, family: String, mut cache: FontCache
) raises -> Int:
    """The rendered width of `text`, for spacing a row legend's sections.

    This used to estimate, as `byte_length * font_size * 0.62`, and was
    wrong two ways (#573). `byte_length` counts UTF-8 bytes, so any
    non-ASCII label was charged for more characters than it has -- a
    two-byte accented letter counted double, a three-byte CJK character
    triple. And a single advance per character is only right for a
    monospaced font, which none of the defaults are.

    Both errors grow with the label, and a row legend laid out from a bad
    width either overlaps its neighbor or leaves a gap where it stopped
    short. Every other label in the library is measured; these were the
    exceptions.

    Args:
        text: The label.
        sc: The render's scaled layout metrics.
        family: The family the label draws in.
        cache: The render's shared font cache.

    Returns:
        The advance width in pixels, rounded up so a section never starts
        inside the label before it.

    Raises:
        Error: Whatever `measure_text()` raises.
    """
    return Int(
        ceil(measure_text(text, sc.font_size, family=family, cache=cache).width)
    )


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
    plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int, *, mut cache: FontCache
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

    var theme = plot._theme
    var sc = _Scaled(theme)
    # Each band is the font size for a plain label, as it always was,
    # and the expression's full height for a math one (#371): a
    # fraction or a superscript reaches past a one-line band and would
    # be clipped by it.
    var extra_top = 0
    if plot._labels.title.byte_length() > 0:
        extra_top += (
            _reserve_height(
                plot._labels.title,
                sc.title_font_size,
                theme.font_family,
                theme.title_bold,
                cache=cache,
            )
            + sc.label_gap
        )
    if plot._labels.subtitle.byte_length() > 0:
        extra_top += (
            _reserve_height(
                plot._labels.subtitle,
                sc.subtitle_font_size,
                theme.font_family,
                False,
                cache=cache,
            )
            + sc.label_gap
        )
    var extra_bottom = 0
    if plot._labels.x_title.byte_length() > 0:
        extra_bottom = (
            _reserve_height(
                plot._labels.x_title,
                sc.axis_title_font_size,
                theme.font_family,
                False,
                cache=cache,
            )
            + sc.label_gap
        )
    var extra_left = 0
    if plot._labels.y_title.byte_length() > 0:
        extra_left = (
            _reserve_height(
                plot._labels.y_title,
                sc.axis_title_font_size,
                theme.font_family,
                False,
                cache=cache,
            )
            + sc.label_gap
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
    *,
    mut cache: FontCache,
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

    # A plain label's baseline sits where it always did -- 0.8 of the
    # size below the top of its band, 0.25 above the bottom for the x
    # caption. A math label's baseline is placed by its own ascent and
    # descent instead, so what rises above or hangs below the line
    # stays inside the band `_apply_labels` reserved for it (#371).
    if plot._labels.title.byte_length() > 0:
        var baseline = Int(sc.title_font_size * 0.8)
        if _needs_math(plot._labels.title):
            baseline = Int(
                ceil(
                    _layout_label(
                        plot._labels.title,
                        sc.title_font_size,
                        theme.font_family,
                        theme.title_bold,
                        cache=cache,
                    ).ascent
                )
            )
        _extend_text_requests(
            text_requests,
            _label_requests(
                plot._labels.title,
                (px0 + px1) // 2,
                oy0 + baseline,
                sc.title_font_size,
                theme.text_color,
                TextAlign.CENTER,
                theme.font_family,
                theme.title_bold,
                0.0,
                cache=cache,
            ),
        )

    if plot._labels.subtitle.byte_length() > 0:
        # Stacks directly below the title's reserved band, which is 0 when
        # there is no title, so a lone subtitle draws at the very top.
        var title_band = 0
        if plot._labels.title.byte_length() > 0:
            title_band = (
                _reserve_height(
                    plot._labels.title,
                    sc.title_font_size,
                    theme.font_family,
                    theme.title_bold,
                    cache=cache,
                )
                + sc.label_gap
            )
        var baseline = Int(sc.subtitle_font_size * 0.8)
        if _needs_math(plot._labels.subtitle):
            baseline = Int(
                ceil(
                    _layout_label(
                        plot._labels.subtitle,
                        sc.subtitle_font_size,
                        theme.font_family,
                        False,
                        cache=cache,
                    ).ascent
                )
            )
        _extend_text_requests(
            text_requests,
            _label_requests(
                plot._labels.subtitle,
                (px0 + px1) // 2,
                oy0 + title_band + baseline,
                sc.subtitle_font_size,
                theme.subtitle_color,
                TextAlign.CENTER,
                theme.font_family,
                False,
                0.0,
                cache=cache,
            ),
        )

    if plot._labels.x_title.byte_length() > 0:
        var above_bottom = Int(sc.axis_title_font_size * 0.25)
        if _needs_math(plot._labels.x_title):
            above_bottom = Int(
                ceil(
                    _layout_label(
                        plot._labels.x_title,
                        sc.axis_title_font_size,
                        theme.font_family,
                        False,
                        cache=cache,
                    ).descent
                )
            )
        _extend_text_requests(
            text_requests,
            _label_requests(
                plot._labels.x_title,
                (px0 + px1) // 2,
                oy1 - above_bottom,
                sc.axis_title_font_size,
                theme.text_color,
                TextAlign.CENTER,
                theme.font_family,
                False,
                0.0,
                cache=cache,
            ),
        )

    if plot._labels.y_title.byte_length() > 0:
        # Rotated a quarter turn counterclockwise, the caption's ascent
        # points left, so its anchor sits that far in from the edge.
        var from_edge = Int(sc.axis_title_font_size * 0.8)
        if _needs_math(plot._labels.y_title):
            from_edge = Int(
                ceil(
                    _layout_label(
                        plot._labels.y_title,
                        sc.axis_title_font_size,
                        theme.font_family,
                        False,
                        cache=cache,
                    ).ascent
                )
            )
        _extend_text_requests(
            text_requests,
            _label_requests(
                plot._labels.y_title,
                ox0 + from_edge,
                (py0 + py1) // 2,
                sc.axis_title_font_size,
                theme.text_color,
                TextAlign.CENTER,
                theme.font_family,
                False,
                -pi / 2.0,
                cache=cache,
            ),
        )

    return text_requests^


def _replay_text_requests[
    T: DrawTarget
](mut target: T, requests: List[_TextRequest], mut cache: FontCache) raises:
    """Draw every `_TextRequest` in `requests` into `target`: the second
    half of every render, after the generic pass has drawn the marks
    and collected the labels.

    One function for every backend, through the trait's `draw_text`,
    `draw_text_runs` and `draw_line_aa`. It replaced a copy per
    backend plus a fourth for `BoundsTarget` (#578): those predated
    `draw_text` on the trait, and once it existed they stayed only
    because the trait form writes an SVG anchor at the backend's fixed
    precision (`x="140.000"`) where the whole-pixel form wrote
    `x="140"`. Same picture; the tests that pinned the markup follow
    the backend. On raster and PDF the trait form is the same code as
    the whole-pixel one, so their output did not move.

    A plain label is `draw_text`; a math label (#371) is one
    `draw_text_runs` call, which on SVG is one `<text>` of `<tspan>`s
    so it stays one string to select or announce (#664); a fraction or
    radical rule is a line. `cache` is read by the raster backend and
    ignored by the vector ones, which resolve no glyphs.

    Args:
        target: Where to draw.
        requests: The labels, in draw order.
        cache: The render's shared font cache.

    Raises:
        Error: Whatever the target's text calls raise.
    """
    for req in requests:
        if req.is_rule():
            target.draw_line_aa(
                req.x,
                req.y,
                req.rule_x2,
                req.rule_y2,
                req.color,
                width=req.rule_thickness,
            )
            continue
        var weight = FontWeight.BOLD if req.bold else FontWeight.NORMAL
        if req.is_runs():
            target.draw_text_runs(
                Float64(req.x),
                Float64(req.y),
                req.runs,
                req.color,
                family=req.family,
                weight=weight,
                rotation=req.rotation,
                cache=cache,
            )
            continue
        target.draw_text(
            Float64(req.x),
            Float64(req.y),
            req.text,
            req.color,
            req.size,
            family=req.family,
            weight=weight,
            rotation=req.rotation,
            align=req.align,
            cache=cache,
        )


def _extend_text_requests(mut dst: List[_TextRequest], src: List[_TextRequest]):
    """Append a copy of every `_TextRequest` in `src` onto `dst`; used by
    the facet/layer renders to gather per-cell/per-layer labels into one
    list.
    """
    for req in src:
        dst.append(req.copy())
