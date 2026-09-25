"""Spike for #827: a chart whose mark is a type.

`Chart[M: MarkType]` holds one `M` and the shared settings; `render()`
is generic over `M`, so a program compiles only the marks it names.
Two marks are wired up, `Bar` and `Gantt`, on the renderers and
encoders phase 2 left behind. Nothing here is imported by the package;
it exists to answer #827's four questions and is not meant to merge.
"""

from canvas.bounds import BoundsTarget
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget
from canvas.vector.pdf import PdfCanvas
from canvas.vector.svg import SvgCanvas

from dataviz.basic.bar import _encode_categorical, _render_bar_oriented
from dataviz.categorical.gantt import _encode_gantt, _render_gantt
from dataviz.core.chart_settings import _ChartSettings
from dataviz.core.mark import Mark
from dataviz.core.plot_fields import (
    _CategoricalData,
    _ContinuousData,
    _ErrorBarData,
)
from dataviz.core.render_result import _RenderResult
from dataviz.core.text import (
    _TextRequest,
    _apply_labels,
    _extend_text_requests,
    _label_text_requests,
    _replay_text_requests,
)
from dataviz.core.theme import Theme
from dataviz.categorical.gantt import _GanttData


trait MarkType(Copyable, Deinitable, Movable):
    """What a mark is to a `Chart`: its runtime id (for the error
    messages and tables that still key on it), two capability
    constants, and a renderer over its own columns."""

    comptime id: Mark
    comptime supports_log_y: Bool
    comptime has_continuous_y: Bool

    def render[
        T: DrawTarget
    ](
        self,
        mut target: T,
        settings: _ChartSettings,
        ox0: Int,
        oy0: Int,
        ox1: Int,
        oy1: Int,
        mut cache: FontCache,
    ) raises -> _RenderResult:
        ...


struct Bar(MarkType):
    """`Mark.BAR` as a type: the categorical x, the values, the error
    bars, and nothing of any other mark."""

    comptime id = Mark.BAR
    comptime supports_log_y = True
    comptime has_continuous_y = True

    var continuous: _ContinuousData
    var categorical: _CategoricalData
    var error_bars: _ErrorBarData

    def __init__(out self):
        self.continuous = _ContinuousData()
        self.categorical = _CategoricalData()
        self.error_bars = _ErrorBarData()

    def render[
        T: DrawTarget
    ](
        self,
        mut target: T,
        settings: _ChartSettings,
        ox0: Int,
        oy0: Int,
        ox1: Int,
        oy1: Int,
        mut cache: FontCache,
    ) raises -> _RenderResult:
        return _render_bar_oriented(
            target,
            Self.id,
            self.continuous,
            self.categorical,
            self.error_bars,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )


struct Gantt(MarkType):
    """`Mark.GANTT` as a type."""

    comptime id = Mark.GANTT
    comptime supports_log_y = False
    comptime has_continuous_y = False

    var gantt: _GanttData
    var categorical: _CategoricalData
    var continuous: _ContinuousData

    def __init__(out self):
        self.gantt = _GanttData()
        self.categorical = _CategoricalData()
        self.continuous = _ContinuousData()

    def render[
        T: DrawTarget
    ](
        self,
        mut target: T,
        settings: _ChartSettings,
        ox0: Int,
        oy0: Int,
        ox1: Int,
        oy1: Int,
        mut cache: FontCache,
    ) raises -> _RenderResult:
        return _render_gantt(
            target,
            self.gantt,
            self.categorical,
            settings,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )


trait Layer(Copyable, Deinitable, Movable):
    """One drawable chart of any mark, for `render_layers`."""

    def width(self) -> Int:
        ...

    def height(self) -> Int:
        ...

    def background(self) -> Color:
        ...

    def draw[
        T: DrawTarget
    ](
        self,
        mut target: T,
        ox0: Int,
        oy0: Int,
        ox1: Int,
        oy1: Int,
        fill_background: Bool,
        mut cache: FontCache,
    ) raises -> List[_TextRequest]:
        ...


struct Chart[M: MarkType](Layer):
    """A chart of one mark type `M` plus the settings every mark shares.

    Built through `Plot2().mark_bar()` and friends; each `mark_*()`
    returns a `Chart` of that mark's type, so what a chart can be asked
    to do is known at compile time.
    """

    var mark: Self.M
    var settings: _ChartSettings
    var _width: Int
    var _height: Int

    def __init__(out self, var mark: Self.M, var settings: _ChartSettings):
        self.mark = mark^
        self.settings = settings^
        self._width = 640
        self._height = 420

    def width(self) -> Int:
        return self._width

    def height(self) -> Int:
        return self._height

    def background(self) -> Color:
        return self.settings.theme.background

    def theme(var self, t: Theme) -> Self:
        self.settings.theme = t
        return self^

    def size(var self, width: Int, height: Int) -> Self:
        self._width = width
        self._height = height
        return self^

    def labels(
        var self,
        title: String = "",
        subtitle: String = "",
        x_title: String = "",
        y_title: String = "",
    ) -> Self:
        self.settings.labels.title = title
        self.settings.labels.subtitle = subtitle
        self.settings.labels.x_title = x_title
        self.settings.labels.y_title = y_title
        return self^

    def scale_y_log(var self) -> Self:
        """A log y axis. Refused at compile time for a mark with no
        continuous y axis, which is the check `render()` makes at run
        time today."""
        comptime assert (
            Self.M.supports_log_y
        ), "scale_y_log(): this mark has no continuous y axis for a log scale"
        self.settings.y_log = True
        return self^

    def encode_categorical(
        var self,
        x: List[String],
        y: List[Float64],
        y_err: List[Float64] = List[Float64](),
    ) raises -> Self where Self.M == Bar:
        """`Plot.encode_categorical()` for a bar chart, and only for a bar
        chart: on any other `Chart[M]` this method does not exist."""
        # `where` constrains the method; it does not retype `self.mark`,
        # so the mark is rebound to the type the clause proved.
        ref bar = rebind[Bar](self.mark)
        _encode_categorical(
            Bar.id,
            bar.continuous,
            bar.categorical,
            bar.error_bars,
            self.settings,
            x,
            y,
            y_err,
            List[Float64](),
            List[Float64](),
        )
        return self^

    def encode_gantt(
        var self,
        categories: List[String],
        start: List[Float64],
        end: List[Float64],
    ) raises -> Self where Self.M == Gantt:
        ref gantt = rebind[Gantt](self.mark)
        _encode_gantt(
            Gantt.id,
            gantt.gantt,
            gantt.continuous,
            gantt.categorical,
            self.settings,
            categories,
            start,
            end,
        )
        return self^

    def draw[
        T: DrawTarget
    ](
        self,
        mut target: T,
        ox0: Int,
        oy0: Int,
        ox1: Int,
        oy1: Int,
        fill_background: Bool,
        mut cache: FontCache,
    ) raises -> List[_TextRequest]:
        """The figure assembly `_draw_figure_into` does for a `Plot`,
        minus the annotation passes: background, title margins, the
        mark, then the titles placed against the inner rect."""
        if fill_background:
            target.fill_rect(
                ox0, oy0, ox1 - ox0, oy1 - oy0, self.settings.theme.background
            )
        var frame = _apply_labels(
            self.settings.labels,
            Self.M.id,
            self.settings.theme,
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )
        var result = self.mark.render(
            target,
            self.settings,
            frame.ox0,
            frame.oy0,
            frame.ox1,
            frame.oy1,
            cache,
        )
        var text = _label_text_requests(
            self.settings.labels,
            self.settings.theme,
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
        _extend_text_requests(text, result.text_requests)
        return text^


struct Plot2(Copyable, Movable):
    """The entry point: settings only, until a `mark_*()` picks the
    mark and the chain becomes a `Chart` of that type."""

    var settings: _ChartSettings

    def __init__(out self):
        self.settings = _ChartSettings()

    def theme(var self, t: Theme) -> Self:
        self.settings.theme = t
        return self^

    def mark_bar(var self, *, horizontal: Bool = False) -> Chart[Bar]:
        self.settings.horizontal = horizontal
        return Chart[Bar](Bar(), self.settings.copy())

    def mark_gantt(var self) -> Chart[Gantt]:
        return Chart[Gantt](Gantt(), self.settings.copy())


def render[M: MarkType](chart: Chart[M]) raises -> Canvas:
    """`render()` for a typed chart: one instantiation per `M` used."""
    var out = Canvas(
        chart.width(), chart.height(), chart.settings.theme.background
    )
    var cache = FontCache()
    var text = chart.draw(out, 0, 0, chart.width(), chart.height(), True, cache)
    _replay_text_requests(out, text, cache)
    return out^


def render_svg[M: MarkType](chart: Chart[M]) raises -> SvgCanvas:
    var svg = SvgCanvas(chart.width(), chart.height())
    var cache = FontCache()
    var text = chart.draw(svg, 0, 0, chart.width(), chart.height(), True, cache)
    _replay_text_requests(svg, text, cache)
    return svg^


def render_pdf[M: MarkType](chart: Chart[M]) raises -> PdfCanvas:
    var pdf = PdfCanvas(chart.width(), chart.height())
    var cache = FontCache()
    var text = chart.draw(pdf, 0, 0, chart.width(), chart.height(), True, cache)
    _replay_text_requests(pdf, text, cache)
    return pdf^


def ink_bounds[M: MarkType](chart: Chart[M]) raises -> BoundsTarget:
    """The bounds pass: draw into a `BoundsTarget`, which paints nothing."""
    var bounds = BoundsTarget(chart.width(), chart.height())
    var cache = FontCache()
    var text = chart.draw(
        bounds, 0, 0, chart.width(), chart.height(), True, cache
    )
    _replay_text_requests(bounds, text, cache)
    return bounds^


def render_layers[*Ls: Layer](*layers: *Ls) raises -> Canvas:
    """Several charts of different mark types on one canvas, sized by
    the first. The point of the spike is the pack, not the layout: each
    layer draws its own frame here, where the real `render_layers`
    agrees a domain and draws one frame."""
    var out = Canvas(
        layers[0].width(),
        layers[0].height(),
        layers[0].background(),
    )
    var cache = FontCache()
    var text = List[_TextRequest]()

    comptime for i in range(layers.__len__()):
        _extend_text_requests(
            text,
            layers[i].draw(
                out,
                0,
                0,
                layers[0].width(),
                layers[0].height(),
                i == 0,
                cache,
            ),
        )
    _replay_text_requests(out, text, cache)
    return out^
