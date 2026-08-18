"""One-call convenience wrappers around `Plot`/`Theme`/`Canvas`/
`render()` for the common case: a single chart, one mark, sane
defaults for everything that isn't the data itself. Every function
here does exactly what examples/bar.mojo's own `main()` does by
hand -- build a `Theme`, build a `Canvas` sized to match, build a
`Plot`, `encode()`/`encode_categorical()` the data onto it, `render()`
into the canvas -- collapsed into one call, because that boilerplate
is identical across almost every example in this package and repeats
it verbatim.

Not a replacement for the fluent `Plot` builder -- facets, layering,
`color`/`size` encoding, and the SVG backend all still need `Plot`
built directly, the same way `examples/` already shows for each of
them. This module is an on-ramp for the single-plot, single-mark
case, sitting *on top of* that builder, not instead of it -- every
function below still ends up calling `Plot`/`render()` itself, so
dropping down to the full builder later (to add a title, a second
series, a facet grid) is a rewrite of the one call this file
replaced, not a different mental model.

One function per mark type, named after the mark, not the `Plot.
mark_*()` method it wraps (`bar`, not `mark_bar`) -- these are meant
to be the first thing a caller reaches for, not a shorthand for
people who already know the builder's own vocabulary. Each takes
whatever shape of data its `encode_*()` counterpart needs (a plain
`(x, y)` pair for the four continuous marks, `(categories, values)`
for every categorical one, and each mark-specific shape beyond that
-- `waterfall()`'s `deltas`, `box()`'s per-category value lists,
`candlestick()`'s OHLC columns, `bullet()`'s measure/target/ranges,
`gantt()`'s start/end, `grouped_bar()`/`stacked_bar()`'s per-series
values -- see each one's own docstring, and `Plot.encode_*()`'s own
in plot.mojo, for what every parameter means).

Each function takes exactly the data its mark needs (see
`Plot.encode()`/`encode_categorical()`'s own docstrings in plot.mojo
for why the shapes differ: continuous `x`/`y` vs. `categories`/
`values`), plus five parameters shared across all of them:

- `theme`: a full `Theme`, for every knob these wrappers don't
  surface as their own parameter (colors beyond `mark_color`,
  margins, font sizes, gridlines, `line_smoothing`, ...) --
  `Theme(mark_color=Color(40, 130, 90))` works exactly as it does
  building a `Plot` by hand; only how it's handed in differs (passed
  as an argument here, instead of chained via `.theme(...)`).
- `width`/`height`: the returned `Canvas`'s pixel size, defaulting to
  640x420 -- the size every example in `examples/` renders at before
  its own supersampling.
- `title`/`x_title`/`y_title`: forwarded to `Plot.labels()` as-is.

Every function returns a `Canvas`, already rendered -- call
`.write_png(path)`/`.write_bmp(path)` (both `canvas_mojo.io`) on the
result. There's no SVG equivalent yet -- build a `Plot` and call
`render_svg()` into an `SvgCanvas` directly for that (see
`examples/scatter_svg.mojo`), same as any mark this file doesn't
cover.
"""

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from dataviz_mojo.theme import Theme
from dataviz_mojo.plot import Plot, render


def scatter(
    x: List[Float64],
    y: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A scatter plot -- `Mark.POINT` over continuous `x`/`y`. See
    this module's own docstring for the shared `theme`/`width`/
    `height`/`title`/`x_title`/`y_title` parameters every function
    here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def line(
    x: List[Float64],
    y: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A line chart -- `Mark.LINE` over continuous `x`/`y`, connected
    in data order. See this module's own docstring for the shared
    parameters every function here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def area(
    x: List[Float64],
    y: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """An area chart -- `Mark.AREA` over continuous `x`/`y`, filled
    down to a zero baseline. See this module's own docstring for the
    shared parameters every function here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_area()
        .encode(x=x, y=y)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def bar(
    categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A bar chart -- `Mark.BAR` over a categorical `x` and continuous
    `y` (see `Plot.encode_categorical()`'s own docstring; one bar per
    entry, negative values extend below the zero baseline
    automatically). See this module's own docstring for the shared
    parameters every function here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=categories, y=values)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def pie(
    categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A pie chart -- `Mark.ARC` over a categorical `x` and continuous
    `y` (the same shape `bar()` takes; every value must be
    non-negative, and at least one positive). Pass `theme=Theme(
    donut_inner_radius_fraction=0.55)` (or any value in `[0.0, 1.0)`)
    for a donut instead -- see `Theme`'s own docstring. See this
    module's own docstring for the shared parameters every function
    here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_arc()
        .encode_categorical(x=categories, y=values)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def lollipop(
    categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A lollipop chart -- `Mark.LOLLIPOP`, the same `(categories,
    values)` shape `bar()` takes (a thin stem plus a point instead of
    a filled rect per category). See this module's own docstring for
    the shared parameters every function here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_lollipop()
        .encode_categorical(x=categories, y=values)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def waterfall(
    categories: List[String],
    deltas: List[Float64],
    is_total: List[Bool] = List[Bool](),
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A waterfall chart -- `Mark.WATERFALL`, floating bars from a
    running total. See `Plot.encode_waterfall()`'s own docstring
    (plot.mojo) for what `deltas`/`is_total` mean, and this module's
    own docstring for the shared parameters every function here
    takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_waterfall()
        .encode_waterfall(categories=categories, deltas=deltas, is_total=is_total)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def box(
    categories: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A box plot -- `Mark.BOX`, one box-and-whiskers per category
    summarizing a whole distribution of raw values (`values[i]`, not
    a single number). See `Plot.encode_boxplot()`'s own docstring
    (plot.mojo) for the quartile/whisker/outlier computation, and
    this module's own docstring for the shared parameters every
    function here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_box()
        .encode_boxplot(categories=categories, values=values)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def candlestick(
    categories: List[String],
    open: List[Float64],
    high: List[Float64],
    low: List[Float64],
    close: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A candlestick chart -- `Mark.CANDLESTICK`, one open/high/low/
    close bar per category. See this module's own docstring for the
    shared parameters every function here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_candlestick()
        .encode_candlestick(categories=categories, open=open, high=high, low=low, close=close)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def bullet(
    categories: List[String],
    measures: List[Float64],
    targets: List[Float64],
    ranges: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A bullet chart -- `Mark.BULLET` (Stephen Few's design): a
    measure bar, a target tick, and shaded qualitative-range bands
    per category. See `Plot.encode_bullet()`'s own docstring
    (plot.mojo) for what `measures`/`targets`/`ranges` mean, and this
    module's own docstring for the shared parameters every function
    here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_bullet()
        .encode_bullet(categories=categories, measures=measures, targets=targets, ranges=ranges)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def gantt(
    categories: List[String],
    start: List[Float64],
    end: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A gantt/span chart -- `Mark.GANTT`, one horizontal bar per
    category from `start[i]` to `end[i]`. See this module's own
    docstring for the shared parameters every function here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_gantt()
        .encode_gantt(categories=categories, start=start, end=end)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def grouped_bar(
    categories: List[String],
    series_names: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A grouped bar chart -- `Mark.GROUPED_BAR`, several bars side
    by side per category, one per series (`values[j]` is series
    `series_names[j]`'s own value per category). See `Plot.
    encode_grouped_bar()`'s own docstring (plot.mojo) for the exact
    shape, and this module's own docstring for the shared parameters
    every function here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(categories=categories, series_names=series_names, values=values)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^


def stacked_bar(
    categories: List[String],
    series_names: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A stacked bar chart -- `Mark.STACKED_BAR`, the exact same
    `(categories, series_names, values)` shape `grouped_bar()` takes,
    each series drawn as a stacked segment instead of a side-by-side
    sub-bar. See this module's own docstring for the shared
    parameters every function here takes."""
    var c = Canvas(width, height, theme.background)
    var plot = (
        Plot()
        .mark_stacked_bar()
        .encode_grouped_bar(categories=categories, series_names=series_names, values=values)
        .labels(title=title, x_title=x_title, y_title=y_title)
        .theme(theme)
    )
    render(c, plot)
    return c^
