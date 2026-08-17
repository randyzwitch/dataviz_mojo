Mojo struct [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/plot.mojo)

# `Plot`

```mojo
@memory_only
struct Plot
```

## Fields

- **x_data** (`List[Float64]`)
- **y_data** (`List[Float64]`)
- **x_categories** (`List[String]`)
- **color_data** (`List[Float64]`)
- **color_categories** (`List[String]`)
- **size_data** (`List[Float64]`)

## Implemented traits

`AnyType`, `Deinitable`, `Movable`

## Methods

### `__init__`

```mojo
fn def __init__(out self)
```

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_point`

```mojo
fn def mark_point(var self) -> Self
```

A scatter plot: one point per (x, y) pair.

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_line`

```mojo
fn def mark_line(var self) -> Self
```

A line plot: (x, y) pairs connected in data order (not sorted by x -- a caller plotting a time series or any other naturally-ordered data gets the order they gave, matching every grammar-of-graphics library's own behavior; sort the data yourself first if that's not the order you want drawn).

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_bar`

```mojo
fn def mark_bar(var self) -> Self
```

A bar chart: one bar per category, encoded via `encode_categorical()` rather than `encode()` -- a bar's x-axis is discrete categories, not continuous positions (see `encode_categorical()`'s own docstring).

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_area`

```mojo
fn def mark_area(var self) -> Self
```

An area chart: the same continuous (x, y) pairs `mark_line()` draws as a stroked line, instead filled from each point down to a zero baseline (`encode()`, not `encode_categorical()` -- an area chart's x-axis is continuous, like a line chart's, not categorical like a bar chart's).

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_arc`

```mojo
fn def mark_arc(var self) -> Self
```

A pie chart: one wedge per category, its angular span proportional to its value -- encoded via `encode_categorical()` (the same category + value data shape `mark_bar()` uses; a pie chart is that same data wrapped around a circle instead of laid out linearly), not `encode()`. Every value must be non-negative, and at least one must be positive -- checked at render() time, the same "raise, don't silently misrepresent the data" stance `_zero_baseline_y_extent` takes for BAR/AREA's own baseline.

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_lollipop`

```mojo
fn def mark_lollipop(var self) -> Self
```

A lollipop chart: one stem-plus-point per category, encoded via `encode_categorical()` -- exactly `mark_bar()`'s own data shape (a bar chart and a lollipop chart differ only in how each category's magnitude is drawn, a filled rect vs. a thin stem with a point at its end, not in what the underlying data means).

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_waterfall`

```mojo
fn def mark_waterfall(var self) -> Self
```

A waterfall chart: one floating bar per category, each running from the previous bar's own cumulative total to the next -- encoded via `encode_waterfall()` (a category + a *signed delta*, not `encode_categorical()`'s plain value; see that method's own docstring).

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_box`

```mojo
fn def mark_box(var self) -> Self
```

A box plot: one box-and-whiskers per category, summarizing a whole distribution of raw values -- encoded via `encode_boxplot()` (a category + a *list* of values, not `encode_categorical()`'s single number per category; see that method's own docstring for the quartile/whisker/outlier computation it does immediately, not deferred to render() time).

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_candlestick`

```mojo
fn def mark_candlestick(var self) -> Self
```

A candlestick chart: one open/high/low/close bar per category (a trading period, typically), encoded via `encode_ candlestick()` -- a category plus four values, not `encode_ categorical()`'s single value (see that method's own docstring).

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_bullet`

```mojo
fn def mark_bullet(var self) -> Self
```

A bullet chart (Stephen Few's design): one measure-vs-target- against-qualitative-ranges composite per category, encoded via `encode_bullet()` -- a category plus a measure, a target, and a whole list of range thresholds, not `encode_categorical()`'s single value.

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_gantt`

```mojo
fn def mark_gantt(var self) -> Self
```

A gantt/span chart: one horizontal bar per category, from a start value to an end value, encoded via `encode_gantt()` -- the first mark whose categories run along the *y*-axis instead of the x-axis (see that method's own docstring).

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_grouped_bar`

```mojo
fn def mark_grouped_bar(var self) -> Self
```

A grouped bar chart: several bars side by side per category, one per series, encoded via `encode_grouped_bar()` -- a category plus a name and a value *per series*, not `encode_categorical()`'s single value.

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `mark_stacked_bar`

```mojo
fn def mark_stacked_bar(var self) -> Self
```

A stacked bar chart: one bar per category, each series' own value stacked as a segment on top of the previous one's own running total, instead of `Mark.GROUPED_BAR`'s side-by-side sub-bars -- encoded via the exact same `encode_grouped_bar()`, no separate encode method needed (the data is identical; only the rendering differs, the same relationship `Mark.LOLLIPOP` already has to `Mark.BAR`'s own `encode_categorical()`).

**Args:**

- **self** (`Self`)

**Returns:**

`Self`

### `encode`

```mojo
fn def encode(var self, x: List[Float64], y: List[Float64], color: List[Float64] = List(), color_categories: List[String] = List(), size: List[Float64] = List()) -> Self
```

Map data columns onto channels. `x`/`y` are required; `color`/`color_categories`/`size` are optional data-driven channels -- when given, each must be the same length as `x`/`y` (checked at render() time, not here, for the same reason `x`/`y`'s own length match is: encode() itself has no way to raise partway through a fluent chain without breaking the chain for every caller who *did* pass matching lengths). Omitting all three (the default, empty lists) means "use Theme's flat `mark_color`/`point_radius`" -- the exact pre-existing behavior, unchanged, for every caller who doesn't need a data-driven channel.

`color` (continuous, `List[Float64]`, mapped through a
`ColorScale` spanning the column's own [min, max]) and
`color_categories` (discrete, `List[String]`, mapped through
`default_categorical_palette()` by each value's position among
the column's *unique* values in first-seen order -- unlike
`encode_categorical()`'s `x`, this one *is* deduplicated,
since a color column is expected to repeat values across many
rows, not name one category per row the way bar categories
do) are mutually exclusive -- passing both raises at render()
time, since there's no principled way to blend a continuous
gradient and a discrete palette into one answer. `size` is
continuous only; a "categorical size" doesn't have an
equivalent meaning the way categorical color obviously does.

Only `Mark.POINT` supports these three channels today -- see
render()'s own check. A per-segment color/width gradient along
a `Mark.LINE` is a real, fancier feature, not silently
approximated by reusing the scatter-point machinery.

For a categorical x-axis (`Mark.BAR`), use
`encode_categorical()` instead -- this method's own `x`
parameter is continuous `Float64` positions, not category
labels.

**Args:**

- **self** (`Self`)
- **x** (`List[Float64]`)
- **y** (`List[Float64]`)
- **color** (`List[Float64]`)
- **color_categories** (`List[String]`)
- **size** (`List[Float64]`)

**Returns:**

`Self`

### `encode_categorical`

```mojo
fn def encode_categorical(var self, x: List[String], y: List[Float64]) -> Self
```

Map a categorical x column and a continuous y column onto the x/y channels -- for `Mark.BAR`, whose x-axis is discrete category labels (mapped through `OrdinalScale`'s evenly spaced bands), not continuous positions the way `encode()`'s own `x` is.

One bar per entry in `x`, in the order given -- `x` is treated
as already being the axis's category order, not deduplicated
or re-sorted; repeated categories (grouped/stacked bars) is a
different, not-yet-built feature (see the wiki's Backlog), not
silently merged.

**Args:**

- **self** (`Self`)
- **x** (`List[String]`)
- **y** (`List[Float64]`)

**Returns:**

`Self`

### `encode_histogram`

```mojo
fn def encode_histogram(var self, data: List[Float64], bins: Int = Int(10)) -> Self
```

Bin `data` into `bins` equal-width intervals and map the result onto the same categorical x/continuous y shape `encode_categorical()` does (a bin's own range, formatted, as its category label; its count as the value) -- for `Mark.BAR`, the same as `encode_categorical()` itself; a histogram *is* a bar chart, just one whose categories are computed from continuous data instead of given directly.

Unlike `encode()`'s own x/y length checks (deferred to
render() time, see that method's own docstring for why), the
binning itself has to happen right here to produce any x/y
data at all, so this raises immediately on `data` that can't
be binned meaningfully: empty, every value identical (zero
span -- there's no width to divide into bins), or `bins <= 0`.

Each bin is a half-open interval `[lo, hi)`, except the very
last bin, which is closed (`[lo, hi]`) so `data`'s own maximum
value -- which would otherwise compute a one-past-the-end bin
index -- lands in the last bin instead of nowhere. Bin edges
are labeled to one decimal place (`_format_fixed`, the same
formatter `LinearScale.ticks()` uses for axis labels) --
enough resolution to distinguish bins for typical real-valued
data without every label growing unreadably long.

**Args:**

- **self** (`Self`)
- **data** (`List[Float64]`)
- **bins** (`Int`)

**Returns:**

`Self`

**Raises:**

### `encode_waterfall`

```mojo
fn def encode_waterfall(var self, categories: List[String], deltas: List[Float64], is_total: List[Bool] = List()) -> Self
```

Map a category column and a *signed delta* column onto `Mark.WATERFALL`'s own floating-bar shape: `deltas[i]` is how much the running total changes at category `i`, not the bar's own absolute height the way `encode_categorical()`'s `y` is for `Mark.BAR` -- each bar is drawn from the running total *before* it (`y0`) to the running total *after* it (`y1`), computed right here as a running cumulative sum starting from 0.0 (the conventional waterfall starting point), not deferred to render() time -- there's no reason to recompute a running sum on every render when the deltas themselves don't change.

`is_total` (default empty -- no row is a total, every row is a
plain rising/falling delta, `Mark.WATERFALL`'s original and
still-default behavior, unchanged) optionally marks specific
rows as running-total *checkpoints* instead: `is_total[i]`
(checked defensively as `False` when `i` falls outside `is_
total`'s own length, so a short/empty list never indexes out of
bounds during this immediate computation -- the actual length-
matches-`categories`-or-is-empty check happens at `render()`
time, like every other length check here) changes only how that
row *draws* -- from `0` up to the running total *after* this
row's own delta is applied, not floating from the total before
to the total after the way a plain delta row does. `deltas[i]`
itself always means the same thing either way, still added to
the running sum every time: a starting-balance total is simply
the first row, marked total, with `deltas[0]` set to that
starting value (so it draws `0` -> the starting balance, and the
running sum now *is* that balance for row 1 to build on); an
ending-balance total is the last row, marked total, with its own
`deltas[i]` left at `0.0` (contributes nothing further, draws
`0` -> whatever the running sum already reached). An intermediate
checkpoint works the same way with a non-zero delta of its own,
if a real use ever wants one. See `examples/waterfall.mojo` for
the conventional start-then-deltas-then-end shape.

Unlike `encode_histogram()`'s binning, this never needs to
raise immediately: a running sum is well-defined for any
(possibly empty) list of deltas, with no degenerate-span case
the way binning has -- `categories`/`deltas` length matching is
still checked, but deferred to render() time like `encode_
categorical()`'s own x/y, for the same reason (see that
method's own docstring). `is_total`, if non-empty, must also
match `categories`' own length -- checked the same deferred way.

`deltas` itself is kept as this Plot's own `y_data` (not just
the derived `y0`/`y1` bounds) so `_render_waterfall` can still
color each non-total bar by its own delta's sign -- see `Theme.
mark_color_negative`'s own docstring; unlike `Mark.BAR`, a
waterfall chart colors by sign unconditionally, not gated by
`Theme.color_by_sign`, since that coloring *is* what a
waterfall chart conventionally shows, not an opt-in extra. A
total row's own `deltas[i]` is stored the same way but never
read for coloring -- see `Theme.waterfall_total_color`'s own
docstring for what colors a total bar instead.

**Args:**

- **self** (`Self`)
- **categories** (`List[String]`)
- **deltas** (`List[Float64]`)
- **is_total** (`List[Bool]`)

**Returns:**

`Self`

### `encode_boxplot`

```mojo
fn def encode_boxplot(var self, categories: List[String], values: List[List[Float64]]) -> Self
```

Map a category column and, per category, a *list* of raw values onto `Mark.BOX`'s own box-and-whiskers shape: unlike every other `encode_*` here, each category's own "y" isn't one number but a whole distribution, summarized immediately (not deferred to render() time) into a five-number summary -- quartiles via linear interpolation (the same method `numpy. percentile`'s own default, `"linear"`, uses, so results match what a caller could independently verify) -- plus every outlier beyond the conventional 1.5*IQR fence, via `_box_stats` (see its own docstring for the exact algorithm).

Raises immediately, the same "can't produce a coherent result
at all, not merely a length mismatch" reasoning `encode_
histogram()`'s own binning raises for: a mismatched `categories`/
`values` length, or any category whose own value list is empty
(quartiles are undefined for zero data points -- there's no
sensible fallback the way an empty histogram bin's count-of-
zero is).

**Args:**

- **self** (`Self`)
- **categories** (`List[String]`)
- **values** (`List[List[Float64]]`)

**Returns:**

`Self`

**Raises:**

### `encode_candlestick`

```mojo
fn def encode_candlestick(var self, categories: List[String], open: List[Float64], high: List[Float64], low: List[Float64], close: List[Float64]) -> Self
```

Map a category column and four continuous value columns (open/high/low/close, the conventional OHLC shape) onto `Mark. CANDLESTICK`'s own wick-plus-body shape -- a category plus *four* numbers, not `encode_categorical()`'s single value.

Unlike `encode_boxplot()`/`encode_histogram()`, nothing here
needs computing up front (no summary statistic, no binning --
every value is drawn exactly as given), so length checking is
deferred to render() time, the same as `encode_categorical()`/
`encode_waterfall()` (see either's own docstring for why: this
method has no way to raise partway through a fluent chain
without breaking it for callers who *did* pass matching
lengths).

**Args:**

- **self** (`Self`)
- **categories** (`List[String]`)
- **open** (`List[Float64]`)
- **high** (`List[Float64]`)
- **low** (`List[Float64]`)
- **close** (`List[Float64]`)

**Returns:**

`Self`

### `encode_bullet`

```mojo
fn def encode_bullet(var self, categories: List[String], measures: List[Float64], targets: List[Float64], ranges: List[List[Float64]]) -> Self
```

Map a category column plus three more columns onto `Mark. BULLET`'s own composite shape: `measures` (the actual value, drawn as a narrower bar), `targets` (a comparison value, drawn as a tick mark), and `ranges` (per category, an ascending list of qualitative-range thresholds -- e.g. `[50.0, 75.0, 100.0]` for a conventional poor/satisfactory/good split -- drawn as shaded background bands from 0 up to each threshold in turn).

Like `encode_candlestick()`, nothing here needs computing up
front (every value is drawn exactly as given), so length
checking -- `categories`/`measures`/`targets`/`ranges` all the
same length, and each category's own `ranges` entry non-empty
and non-decreasing (the band-stacking math in `_render_bullet`
depends on that order) -- is deferred to `render()` time, the
same as every other categorical `encode_*` here (see `encode_
categorical()`'s own docstring for why).

**Args:**

- **self** (`Self`)
- **categories** (`List[String]`)
- **measures** (`List[Float64]`)
- **targets** (`List[Float64]`)
- **ranges** (`List[List[Float64]]`)

**Returns:**

`Self`

### `encode_gantt`

```mojo
fn def encode_gantt(var self, categories: List[String], start: List[Float64], end: List[Float64]) -> Self
```

Map a category column and two continuous value columns (`start`/`end`) onto `Mark.GANTT`'s own horizontal-span shape -- a category plus a range, not `encode_categorical()`'s single value. Deliberately plain `Float64`, the same as every other `encode_*` here, not a dedicated date/time type -- this whole package has no `Date`/`Time` type anywhere (see dataviz-api- design's own "plain columnar arrays are the whole data model" decision), so a project schedule's own dates are just numbers here (day-of-year, a Unix timestamp, whatever a caller's own data already uses) the same way every other numeric column in this package is -- which is also exactly why this mark doubles as a generic "span chart" for any numeric start/end range per category, not something scheduling-specific.

Like `encode_candlestick()`, nothing needs computing up front,
so length checking (`categories`/`start`/`end` all the same
length) is deferred to `render()` time, the same as every other
categorical `encode_*` here. `start[i] > end[i]` isn't checked
or rejected either -- `_render_gantt` draws from `min(start[i],
end[i])` to `max(...)`, the same "use min/max rather than
assume an order" tolerance `Mark.CANDLESTICK`'s own open/close
handling already has, so a reversed pair still renders
sensibly rather than raising over what's likely just a data
convention difference, not an error.

**Args:**

- **self** (`Self`)
- **categories** (`List[String]`)
- **start** (`List[Float64]`)
- **end** (`List[Float64]`)

**Returns:**

`Self`

### `encode_grouped_bar`

```mojo
fn def encode_grouped_bar(var self, categories: List[String], series_names: List[String], values: List[List[Float64]]) -> Self
```

Map a category column plus *several* value series onto `Mark.GROUPED_BAR`'s own side-by-side-bars-per-category shape -- `values[j]` is series `series_names[j]`'s own value for every category (so `values[j][i]` is series `j`'s value for `categories [i]`), the same "outer list indexes the thing being repeated, inner list indexes categories" shape `encode_boxplot()` already established for a *distribution* per category -- here it's a *series* per category instead.

Nothing needs computing up front, so length checking (`series_
names`/`values` the same length, and every `values[j]` the same
length as `categories`) is deferred to `render()` time, the same
as every other categorical `encode_*` here.

**Args:**

- **self** (`Self`)
- **categories** (`List[String]`)
- **series_names** (`List[String]`)
- **values** (`List[List[Float64]]`)

**Returns:**

`Self`

### `theme`

```mojo
fn def theme(var self, t: Theme) -> Self
```

**Args:**

- **self** (`Self`)
- **t** (`Theme`)

**Returns:**

`Self`

### `labels`

```mojo
fn def labels(var self, title: String = "", x_title: String = "", y_title: String = "") -> Self
```

Set the chart title and/or axis titles -- text captions, not data. Named `x_title`/`y_title`, not `x`/`y`, so a call site reading `.labels(x_title=..., y_title=...)` next to `.encode(x= ..., y=...)` never reads as if it's setting data columns; the two mean completely different things (a caption string vs. a `List[Float64]`) despite the visual similarity.

Each of the three is independent and defaults to `""` (not
set) -- call with only the ones actually wanted, e.g. `.labels
(title="Quarterly Revenue")` alone, with no axis titles at all.
`render()`/`render_svg()` reserve layout space for exactly the
ones that are non-empty and no others (see their own docstring
for the margin math) -- an unset title costs nothing, the same
"absent means absent" rule this file's other optional features
(`Theme.line_smoothing`, `donut_inner_radius_fraction`, etc.)
already follow.

`x_title`/`y_title` caption whatever's drawn along the bottom/
left edge respectively -- which axis that actually *is*
depends on the mark's own orientation (the continuous axis for
`Mark.POINT`/`LINE`/`AREA`/`GANTT`'s own `x`; the categorical
one for every vertical categorical mark's own `x`; `GANTT`'s
own categorical `y` instead of a continuous one) -- `x_title`/
`y_title` describe screen position, not "the continuous axis"
specifically, so the same two names stay meaningful across
every orientation without special-casing.

`Mark.ARC` has no x/y axes at all (see `_render_arc`'s own
docstring) -- `x_title`/`y_title` raise at render() time if set
on an `Mark.ARC` plot (only `title` applies there), the same
"raise on a setting that can't apply, don't silently drop it"
rule `Plot.encode`'s own color/size-on-a-non-POINT-mark check
already follows.

**Args:**

- **self** (`Self`)
- **title** (`String`)
- **x_title** (`String`)
- **y_title** (`String`)

**Returns:**

`Self`


