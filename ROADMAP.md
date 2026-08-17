# dataviz roadmap

What exists, and what's still an open design question. This package
is a deliberately small first vertical slice, not a scaled-down
version of the eventual API -- built specifically so real rendered
output could inform the remaining grammar decisions (encoding
channels beyond x/y, facets, layers, a Table/DataFrame data source)
instead of guessing at them up front. See the conversation this came
out of for the full paradigm discussion (grammar-of-graphics vs.
Vega/Vega-Lite vs. d3 vs. ECharts vs. matplotlib) and why
grammar-of-graphics, compiled in one batch pass straight to `canvas`
calls, won out.

## Done

- **`theme.mojo`** — `Theme`: colors (background/mark/axis/gridline/
  text), sizes (font size, point radius, line width), margins, and a
  gridlines on/off flag. One small config struct rather than a dozen
  optional parameters scattered across `Plot`'s own builder methods --
  deliberately the one place this package borrows ECharts' "config
  object" ergonomics rather than the grammar-of-graphics vocabulary
  everything else follows, since a theme doesn't change what a mark or
  scale *means*, only how it looks.
- **`mark.mojo`** — `Mark` (POINT/LINE), the same small-struct-with-
  `comptime`-constants-and-`__eq__` pattern `canvas_mojo.FillRule`/
  `canvas_mojo.TextAlign` already established. Deliberately just these two
  for now -- the two basic X-Y plot types the user asked to see first,
  not the full mark vocabulary (bar/area/arc) a real grammar-of-
  graphics library eventually wants.
- **`scale.mojo`** — `LinearScale`: a domain-to-range affine map whose
  `scale()`/`translate()` are exactly the slope/intercept
  `canvas_mojo.geometry.Transform2D` takes (that type's own docstring
  already named this as the deferred piece) -- `Plot`/`render()`
  build one `Transform2D`-equivalent per axis via `to_pixel()` calls
  rather than duplicating Transform2D's math (see plot.mojo). A
  reversed range (range_min > range_max in pixel terms) is how the
  y-axis gets its flip; no separate flag needed, the slope just comes
  out negative.

  `ticks()` is the one genuinely new algorithm in this package: Paul
  Heckbert's "nice numbers for graph labels" (Graphics Gems, 1990) --
  round an ideal step size up to the nearest 1/2/5/10-times-a-power-
  of-ten so axis labels read as 0.2/0.4/0.6, not whatever a raw
  `(max-min)/n` division happens to produce. Every example in
  `scale.mojo`'s own module docstring (domain [0,100] -> step 20,
  [3,27] -> step 5, [-50,50] -> step 20, [0,0.01] -> step 0.002) was
  independently computed by hand before trusting the Mojo
  implementation, then locked into `test_scale.mojo`. A zero-span
  domain (a constant-valued column) is a real, handled case -- one
  tick at that value, not a crash from `log10(0)`.

  `_format_fixed` exists because plain `String(Float64)` isn't usable
  for tick labels -- confirmed by probe that e.g. `0.0 + 3*0.1` prints
  as `"0.30000000000000004"`, ordinary binary-floating-point drift
  unrelated to this module's own math. Rounds to the decimal count
  `ticks()` already computed (from the same nice-step exponent, not a
  second guess at how many decimals a value "needs") and builds the
  string by hand rather than trusting float formatting a second time.
- **`plot.mojo`** — `Plot` (fluent builder: `Plot().mark_point().
  encode(x=..., y=...).theme(...)`, consuming and returning `Self` so
  calls chain -- confirmed this pattern actually compiles in this
  Mojo version via probe before committing to it) and `render(canvas,
  plot)`, the single batch entry point: background, gridlines, axis
  lines, tick marks + labels, then the mark itself, back to front.
  `encode()` takes plain `List[Float64]` columns directly (the
  data-model decision made before any of this was written -- a
  Table/DataFrame layer can resolve named fields down to these same
  lists later without changing this contract). Mismatched x/y column
  lengths `raise` at `render()` time (encode() itself can't raise
  without breaking the fluent chain for callers who pass matching
  lengths).

  Every draw call `render()` makes is the AA variant -- points via
  `fill_circle_aa`, lines via `stroke_path_aa`, and (this was a
  deliberate follow-up decision, not the original choice) gridlines/
  axis lines/tick marks via `draw_line_aa` rather than `canvas`'s
  hard-edged `draw_line`. For those axis-aligned lines specifically
  it's not fixing a visible jaggedness problem -- confirmed directly
  against `draw_line_aa`'s own coverage math that a perfectly
  horizontal/vertical, integer-positioned line has no diagonal
  stepping to smooth in the first place, so the pixel output is the
  same either way (full suite re-run afterward with zero test changes
  needed, confirming this in practice, not just in theory) -- but
  there's no real cost to it given how few short lines these are, and
  "every draw call defaults to AA" is a simpler rule to hold in your
  head than an exception that has to be re-justified per call site.

  The data domain gets 5% padding on each side (a single data point,
  or a constant-valued column, gets a fixed 1.0 padding instead of 5%
  of a zero span) so marks never look clipped sitting exactly on a
  plot edge -- a deliberate, documented choice, not an oversight if a
  future caller wants edge-to-edge axes instead.

  Rendered pixel positions hand-derived and verified, not just
  visually spot-checked: a single point at data (5,5) on a 400x300
  canvas with default margins lands its circle's center at exactly
  pixel (220,135), solved directly from LinearScale's own slope/
  intercept formula. Also viewed both example outputs
  (`examples/scatter.mojo`, `examples/line.mojo`) as rendered PNGs
  before considering this done, not just trusting the pixel-level
  tests in isolation.
- **`color_scale.mojo`** — `ColorScale`, continuous data-driven color
  encoding (`Plot.encode(color=...)`), and continuous size encoding
  (`Plot.encode(size=...)`, reusing `LinearScale` directly -- a data
  value mapped to a pixel *radius range* is exactly the same linear
  map as a data value mapped to a pixel *position*, no new scale type
  needed). `ColorScale` shares its stop-interpolation math with
  `canvas_mojo.gradient`'s `LinearGradient`/`RadialGradient` via that
  module's own `_color_at_t`/`_GradientStop` rather than
  reimplementing it -- identical math, only the projection differs (a
  data domain here, vs. a pixel position there).

  Both channels are optional and purely additive: omitting `color`/
  `size` from `encode()` (an empty list, the default) reduces to
  exactly the prior flat-`mark_color`/fixed-`point_radius` behavior,
  confirmed by the full pre-existing test suite passing unchanged.
  Scoped to `Mark.POINT` only for now -- `render()` raises if `color`/
  `size` data is given alongside `Mark.LINE`, a real error rather than
  a silent no-op, since a per-segment color/width gradient along a
  line is a different, fancier feature this doesn't attempt to
  approximate. Categorical color (mapping category names to a
  palette) is deferred until `OrdinalScale` exists (see "Explicitly
  still open" below) -- the same dependency `Mark.BAR`'s categorical
  x-axis has, so both land together.

  `MinMax`/`_min_max` (scale.mojo) factored out of what was
  `Plot._data_extent`'s own inline min/max scan, shared now by three
  callers: `_data_extent` (which pads the result 5% for spatial axes)
  and the new color/size domains (which don't pad -- a legend's
  extremes should mean exactly the data's own extremes). Hand-verified
  end to end: two points' exact pixel centers solved from
  `LinearScale`'s slope/intercept formula (matching the existing
  single-point test's own methodology), then color checked for an
  exact black/white match at the domain's two ends, size checked by
  comparing coverage at a fixed distance from each center (3px from a
  radius-2 point is background, the same 3px from a radius-10 point is
  still solidly covered) -- confirming the two points actually got
  visibly different treatment, not just "some circle was drawn twice."
  Also viewed `examples/bubble.mojo` (a classic bubble chart: both
  channels driven by the same third variable) as a rendered PNG before
  considering this done.

- **`ordinal_scale.mojo` / `Mark.BAR`** — `OrdinalScale`, the first
  categorical scale (evenly spaced pixel "bands," d3's `scaleBand` in
  spirit: one `padding` fraction split evenly around each band, not
  separate inner/outer padding knobs -- this package's usual "minimal,
  not a port of everything a mature library offers" approach), and
  `Mark.BAR` built on it. Purely index-based (`band_start(i)`, not
  `band_start(category_string)`) -- a bar chart's data already pairs
  each row's category with its own position in the same row, so there
  was never a real need to search the domain by string equality; the
  domain list itself doubles as the lookup, avoiding both the
  complexity and the "what if two categories collide" edge case a
  string-keyed API would have to answer for no actual benefit here.

  `Plot.encode_categorical(x: List[String], y: List[Float64])` is a
  new, separate method from `encode()`, not an overload or an
  additional optional parameter on it -- `Mark.BAR`'s x-axis is
  categorical, so its own `x` parameter is a genuinely different type
  (`List[String]`, not `List[Float64]`), and a caller should never be
  unsure which one a given mark type wants. One bar per entry, in the
  order given -- not deduplicated or sorted; grouped/stacked bars
  (repeated categories) is real, separate, not-yet-built work (see
  below).

  `_render_bar` is a deliberately separate function from `render()`'s
  own continuous-x path (see its own docstring for why: `OrdinalScale`
  and `LinearScale` differ enough -- band positions from an index vs.
  one slope/intercept formula -- that sharing would mean a mark-type
  branch on nearly every line, not a clean shared core), duplicating
  the y-axis gridline/tick/label loop rather than force a premature
  abstraction across two call sites for the one genuinely identical
  piece (same "a bit of duplication over a shared abstraction for two
  call sites" tolerance `path.mojo`'s `fill_path_gradient` docstring
  already states). No x-gridlines for bars -- the bars themselves
  already visually separate categories, unlike a continuous scatter/
  line axis where a gridline carries real information.

  `_bar_y_extent` is the one real, non-cosmetic difference from the
  continuous marks' own `_data_extent`: a bar's height/area encodes
  magnitude, so its y-domain always includes an exact zero baseline
  (arguably the single most common real charting-correctness mistake,
  avoided here by construction rather than left for a caller to
  remember) -- only the non-zero-crossing end gets the usual 5%
  padding; zero itself is never "padded away from," confirmed with a
  dedicated negative-value test (a bar's zero baseline lands at the
  domain's own unpadded top edge when every value is negative,
  extending *downward* from it, not upward the way every positive-only
  bar in the sibling test does).

  Every pixel position hand-derived in Python before trusting the
  Mojo implementation (band edges from `OrdinalScale`'s own formula,
  bar tops/baseline from `_bar_y_extent` composed with `LinearScale`'s
  existing slope/intercept math) -- both matched the actual rendered
  output exactly on first run. Also viewed `examples/bar.mojo`
  (weekday values including one negative) as a rendered PNG, showing
  the negative bar correctly extending below the zero line, before
  considering this done.
- **Categorical color encoding** —
  `Plot.encode(color_categories=...)`, a discrete sibling to the
  continuous `color=...` channel: category names mapped through
  `default_categorical_palette()` (8 visually-distinct colors, cycled
  via modulo past that) by each value's position among the column's
  *unique* values in first-seen order. Deliberately *not* built on
  `OrdinalScale` the way this file previously expected -- a color
  column is expected to repeat values across many rows (many points
  share one category), unlike `encode_categorical()`'s `x`, which is
  one entry per bar already; the actual new piece needed was
  `_unique_categories` (dedup, first-seen order) plus `_index_of`, not
  `OrdinalScale`'s band math, which has nothing to do with color at
  all. `color` and `color_categories` are mutually exclusive -- passing
  both raises at render() time, since there's no principled way to
  blend a continuous gradient and a discrete palette into one answer.

  `default_categorical_palette()` is a plain function, not a `Theme`
  field, confirmed necessary by direct probe: adding a `List` field to
  `Theme` breaks its `ImplicitlyCopyable` conformance (Mojo can't
  synthesize an implicit copy constructor once a struct holds a
  `List`), which every existing `var theme = plot._theme`-style copy
  throughout this package already depends on. Matches the same
  reasoning `canvas_mojo.Color`'s own history gives for keeping named
  palettes out of the core `Color` type -- a fixed default now,
  per-Theme customization only once that's an actual concrete need.

  Hand-verified two ways: `_unique_categories`/`_index_of` tested
  directly (dedup order, found/not-found positions) rather than only
  through a full render, plus one end-to-end render test confirming
  two categories land on `default_categorical_palette()[0]`/`[1]`
  exactly, at the same hand-derived pixel centers the continuous-color
  test already established. Also viewed `examples/categorical_color.mojo`
  (an iris-species-style scatter, 3 groups) as a rendered PNG before
  considering this done.

- **`Mark.AREA`/`Mark.ARC`** — the last two mark types this round.
  `Mark.AREA` shares `Mark.LINE`'s continuous `encode()` data and its
  own point-to-point path construction, but closes the path down to a
  zero baseline and fills it (`fill_path_aa`) instead of stroking it
  -- reusing `_zero_baseline_y_extent` (renamed from `_bar_y_extent`,
  since the "always include zero" correctness argument turned out to
  be about magnitude-encoding marks generally, not bars specifically)
  for the identical reason `Mark.BAR` needed it: an area's fill
  encodes magnitude from a baseline exactly the way a bar's height
  does.

  `Mark.ARC` (pie charts) reuses `encode_categorical()` -- the same
  category + value data shape `Mark.BAR` already has, since a pie
  chart is that same data wrapped around a circle instead of laid out
  linearly, not a reason to invent a third data shape. Wedge colors
  reuse `default_categorical_palette()` by category index, the exact
  mechanism `color_categories` encoding already established, so a pie
  chart and a categorical-color scatter plot describing the same data
  get visually consistent colors. Wedges start at 12 o'clock and
  sweep clockwise -- confirmed directly (not assumed) which direction
  increasing angle actually sweeps on screen given `canvas`'s y-down
  pixel convention, via a hand-derived test checking a point directly
  right of center lands in the first wedge and a point directly left
  lands in the second, for two equal-value wedges. Values must be
  non-negative with a positive total -- a real error, not a silently
  degenerate or misleading chart, since an angular span proportional
  to a negative or all-zero value has no coherent meaning.

  `Mark.ARC` has no x/y axis frame at all (no ticks, gridlines, axis
  lines) -- structurally different enough from every other mark that
  it renders through its own fully separate `_render_arc`, the same
  "separate function over a mark-type branch threaded through nearly
  every line" reasoning `_render_bar` already established.

  Viewed `examples/area.mojo` (a sine wave) and `examples/pie.mojo`
  (five browser market-share wedges) as rendered PNGs before
  considering this done.
- **Legends** — `_draw_legend`, a small swatch-plus-label list, for
  the two mark/channel combinations that already reduce to "a list of
  category labels plus the palette that colored them": `Mark.POINT`
  with `color_categories`, and `Mark.ARC` (every wedge is already
  categorical by construction). Continuous color/size encoding has no
  legend yet -- a real, structurally different rendering job (a
  gradient bar or representative sizes, not a swatch list), not a
  small extension of this (see "Explicitly still open," below).

  On by default (`Theme.show_legend`) whenever there's something to
  show -- matching every other grammar-of-graphics/charting library's
  own default (a color-categorical plot without a legend is close to
  unreadable, since there's no other way to know what the colors
  mean), not an opt-in a caller has to remember. Reserves a fixed
  130px column on the right (`_LEGEND_WIDTH`) only when actually
  shown, narrowing the plot area / pie radius accordingly -- confirmed
  both ways: a dedicated test checks the *narrowed* layout's own
  hand-derived pixel positions when the legend is on, and a second
  test confirms `show_legend=False` restores the *exact* original
  full-width pixel positions the no-legend tests already established,
  not just "no legend pixels appear."

  Every legend row's color is looked up the identical `i %
  len(palette)` way the actual points/wedges were colored (not
  `labels[i]`'s own index), so a legend can never show a different
  color than what was actually drawn, cycling included. Also viewed
  `examples/categorical_color.mojo` and `examples/pie.mojo` again
  (both already existed; the legend simply appears now that
  `show_legend` defaults on) as rendered PNGs before considering this
  done.
- **Dynamic left margin** — `Theme.margin_left` is now a *minimum*,
  not the final value: `render()`/`_render_bar` compute the y-axis's
  own tick labels (via `LinearScale.ticks()`) *before* the pixel range
  -- and so the plot area's left edge -- is finalized, since a scale's
  tick values (and their formatted label text) depend only on
  `domain_min`/`domain_max`, never on `range_min`/`range_max` (see
  `LinearScale.ticks()`'s own docstring); `_max_label_width` then
  measures those labels via `canvas_mojo.text.measure_text` (plain
  `measure_text`, not `measure_text_block` -- axis labels are always
  single-line and unrotated, so the simpler function is the right
  one, not the one built for rotation/multi-line), and `plot_x0`
  becomes `max(theme.margin_left, measured_width + tick_length +
  label_gap + buffer)`.

  Purely additive by construction, confirmed empirically, not just
  argued: every pre-existing hand-derived pixel-position test in this
  file (all using short labels like "20"/"A") kept passing completely
  unchanged when this was added, and a dedicated pair of tests locks
  in both directions -- short labels leave `plot_x0` at exactly
  `Theme`'s configured default, wide labels (`measure_text`'s own
  real output for "2000000" et al., confirmed by probe against this
  environment's actual font metrics, the same "locked in, confirmed
  by probe" convention `canvas`'s own text tests already use) grow it
  well past that default, checked against exactly where the y-axis
  line itself lands, not an indirect proxy for it. One real mistake
  caught by that same probe-first discipline, not shipped: the first
  version of the "grew" test also asserted the *old* fixed-margin
  position was plain background once the margin grew -- wrong, since
  covering that space with the wide label's own ink is the entire
  point of the feature; fixed to check for the label's own ink
  reaching past the old margin instead, once the probe showed what
  was actually there. Also viewed `examples/dynamic_margin.mojo`
  (seven-digit y-values) as a rendered PNG, confirming no clipping or
  crowding, before considering this done.
- **Facets / small multiples** — `render_facets(canvas, plots, cols)`
  lays a `List[Plot]` out in an evenly sized grid on one canvas, each
  cell fully independent (its own margins, axes, mark type, even its
  own `Theme`) rather than one shared coordinate system split into
  panels. Built by giving `render()` itself (and `_render_bar`/
  `_render_arc`, threaded through the same way) optional `ox0`/`oy0`/
  `ox1`/`oy1` outer-bounds parameters -- defaulting (`ox1`/`oy1`'s `-1`
  sentinel resolving to `canvas.width`/`canvas.height`) to the exact
  prior "whole canvas" behavior, so every existing single-plot
  `render(canvas, plot)` call needed zero changes -- confirmed, not
  just argued: all 30 pre-existing `test_plot.mojo` tests kept passing
  completely unchanged once this landed. `render_facets` itself is a
  thin composition on top: it never draws a pixel directly, only
  computes each cell's bounds (`canvas.width * col // cols`, not
  `col * (canvas.width // cols)` -- the two differ whenever the
  canvas doesn't divide evenly, and only the first form guarantees
  adjacent cells share the exact boundary pixel with no gap or 1px
  overlap, confirmed directly by working the expressions, not
  assumed) and calls `render()` once per plot with that cell's bounds.
  A trailing incomplete row's empty cells are simply never rendered
  into, left exactly as the canvas already was -- not stretched or
  blanked specially.

  Four new hand-derived tests, reusing (not re-solving from scratch)
  the exact plot-area math `test_render_point_mark_centers_on_the_
  hand_derived_pixel` had already worked out for a single (5.0, 5.0)
  point on a 400x300 canvas with Theme's default margins (plot area
  x:[60,380], y:[20,250], point pixel (220,135)): a facet cell is
  that identical geometry, just offset by the cell's own origin (an
  800x300 canvas split 2 cols x 1 row reproduces cell 0 exactly, and
  cell 1's point lands at exactly (220,135) shifted +400 in x, to
  (620,135) -- confirmed by re-deriving `LinearScale.to_pixel`'s own
  slope/intercept formula with the shifted range, not by assuming the
  offset carries over uniformly). Also covers a 2x2 grid where the
  4th cell has no matching plot (confirmed genuinely untouched --
  canvas pre-filled with a color no Theme default produces, so a
  coincidental match can't hide a bug), and `cols <= 0` raising.
  Viewed `examples/facets.mojo` (four regions' quarterly revenue,
  each its own line chart and color, arranged 2x2) as a rendered PNG
  before considering this done.
- **`Theme.scale`: render the same chart at a higher pixel density** —
  motivated by a concrete, reported problem: every example canvas here
  is small (640x420 and similar), and text/thin strokes in the
  rendered output looked fuzzy. The first hypothesis (a viewer
  stretching a small raster image to fill more of a pane, smoothing
  the upscale in the process) was confirmed empirically -- the same
  scatter scene rendered once at 640x420 and once at 1280x840 (every
  Theme size doubled by hand alongside the canvas) looked visibly
  crisper at 2x through the same viewing pipeline -- but shipping
  *that* as the fix (bigger canvas, bigger output file) was correctly
  rejected on review: it only looks sharper in a viewer that happens
  to scale the bigger file back down to fit some display area, which
  is exactly the viewer-dependent workaround being avoided, not a
  real per-pixel quality improvement, and does nothing for a viewer
  that shows images at native pixel size. `Theme.scale` itself is
  still real and still useful -- rendering the *identical* chart at a
  higher pixel density is a genuine, generically useful capability --
  but "increase sharpness" needed one more piece: `canvas_mojo/resize.mojo`'s
  new `downsample()` (see canvas_mojo/ROADMAP.md's own entry for the full
  supersampling story) is what every `dataviz_mojo/examples/` file actually
  pairs `scale` with now -- render 3x, then shrink back down to the
  original target size -- see this section's own closing paragraph for
  how the two compose.

  `scale` (default 1.0, purely multiplicative -- see Theme's own
  docstring) is one new `Theme` field that uniformly multiplies every
  *other* pixel-sized quantity `render()`/`_render_bar`/`_render_arc`/
  `_draw_legend` compute -- font size, margins, point radius, line
  width, size-encoding's range, and the module-private layout
  constants (`_TICK_LENGTH`, `_LABEL_GAP`, `_LEGEND_WIDTH`,
  `_LEGEND_SWATCH_SIZE`, `_LEGEND_ROW_GAP`, `_MARGIN_BUFFER`) that
  used to be un-scalable by construction. A caller who wants a crisp
  2x render now only sets `Theme(scale=2.0)` and doubles the Canvas --
  no longer the by-hand, easy-to-miss-one-constant process the initial
  probe above needed (that probe left the legend's own swatch/row-gap
  sizing un-doubled, since those were private constants with no Theme
  field at all -- directly why this became a proper feature instead of
  "just render examples bigger").

  Implementation: a private `_Scaled(theme)` struct, constructed once
  near the top of each of the four functions above, computes every
  `* theme.scale` value exactly once -- the single place that formula
  lives, so it can't drift between render paths the way hand-scaling
  every call site individually risked. `_data_extent`/
  `_zero_baseline_y_extent`'s own padding (a *fraction* of the data's
  span, not a pixel quantity) and `OrdinalScale`'s own band padding
  (also fractional) are correctly untouched -- resolution-independent
  by construction, not accidentally omitted.

  Purely additive by construction, confirmed the same way dynamic
  margins/legends were: `scale`'s own default of 1.0 reproduces the
  pre-existing unscaled output exactly -- every one of the 38
  pre-existing `test_plot.mojo` tests kept passing completely
  unchanged, and a dedicated test compares a bare-default render
  against an explicit `Theme(scale=1.0)` render pixel-for-pixel across
  the entire canvas, not just at a few sampled points. A second test
  hand-derives `scale=2.0`'s own plot area and point pixel (reusing,
  not re-deriving, the single-(5.0, 5.0)-point math test_render_
  point_mark_centers_on_the_hand_derived_pixel already worked out --
  every margin exactly doubled, and the point's own pixel lands on
  exactly double the 1x pixel, confirmed via `LinearScale.to_pixel`'s
  own formula, not assumed to "just carry over").

  One real bug caught before this shipped, not after: an early
  `Edit` attempt to thread `_Scaled` through `_draw_legend`'s own
  docstring/body failed to match the file's actual text on the first
  try (a stale in-memory copy of a docstring paragraph vs. what was
  really on disk) -- caught immediately by the tool's own "string not
  found" error rather than silently editing the wrong thing, re-read
  the real content, and retried against it.

  Every existing example in `dataviz_mojo/examples/` now renders at 3x
  (`Theme.scale=3.0` on a canvas 3x its own target width/height), then
  `downsample()`s that back down to the *original* target dimensions
  before writing the output file -- true supersampled anti-aliasing,
  baked into a file the same size as before this feature existed, not
  a bigger file that only looks sharper if a viewer happens to shrink
  it back down (see `examples/scatter.mojo`'s own docstring, which the
  rest cross-reference rather than repeating the same paragraph, and
  `canvas_mojo/resize.mojo`'s own docstring for `downsample()` itself).
  `render_facets()`'s own example (`examples/facets.mojo`) confirms
  this composes cleanly with facets too: `downsample()` runs once,
  after every cell has been drawn, on the whole shared canvas -- it's
  a plain per-pixel box filter with no idea cells exist, so a
  multi-cell facet canvas needs no special handling. All nine examples
  re-viewed as rendered PNGs -- both the plain 1x and the 3x-then-
  downsampled version of the scatter scene, at their own genuinely
  identical 640x420 dimensions, side by side -- before considering
  this done.
- **`render_svg()`: a vector rendering backend, alongside raster** —
  raised as a direct question against the whole `Theme.scale`/
  `downsample()` effort above: starting from a raster foundation means
  patching resolution/sharpness problems onto it after the fact, when
  a vector format has no fixed pixel grid to lose sharpness at in the
  first place. The honest answer -- yes for sharpness specifically,
  but no for the raster investment as a whole -- led to adding SVG as
  a second backend `Plot` renders through, not a replacement for the
  first (see canvas_mojo/ROADMAP.md's own `DrawTarget`/`SvgCanvas` entry
  for the trait design and the two real wrong turns building it took,
  including a genuine Mojo ownership-tracking limitation hit and
  abandoned along the way).

  `render()`/`render_svg()` now both delegate to one shared, generic
  rendering core (`_render_generic`, `_render_bar`, `_render_arc` --
  each `[T: DrawTarget]`) for every shape (gridlines, axis lines,
  points, bars, wedges, stroked/filled paths) -- the *exact* same code
  runs for both backends, not two parallel implementations kept in
  sync by hand. Confirmed empirically, not just by construction: every
  one of the 40 pre-existing raster tests kept passing completely
  unchanged after this refactor, since `render()`'s own public
  signature and behavior are untouched -- it's now a thin wrapper
  (resolve `ox1`/`oy1` sentinels against `Canvas.width`/`.height`, call
  the generic core, draw the text it hands back) around what used to
  be its own body directly.

  Text is the one thing that isn't generic: `DrawTarget` deliberately
  has no `draw_text` method (originally to keep `canvas`'s then-Cairo
  dependency opt-in; `canvas_mojo` has since dropped Cairo entirely in
  favor of its own native FreeType/fontconfig text stack -- see that
  repo's own history -- but the same split still holds for the same
  reason: raster text drawing and SVG markup emission are two
  genuinely different operations, not implementations of one shared
  interface). Instead `_render_generic`/`_render_bar`/`_render_arc`
  collect every axis/tick/legend label as a `List[_TextRequest]`
  (position, string, color, size, alignment -- plain data, nothing
  drawn yet) while the shape-drawing pass runs, and return it;
  `render()` replays that list through `canvas_mojo.text.draw_text`,
  `render_svg()` replays the identical list through `SvgCanvas.
  draw_text` (plain markup emission, no font/glyph machinery involved
  at all). Text ends up
  drawn *after* every shape this way, not interleaved the way the pre-
  refactor code drew it -- confirmed harmless, not just assumed: axis/
  tick text lives in the margin and legend text in the legend column,
  both regions marks and swatches never overlap by construction (the
  entire point of `Theme.margin_left`/`_LEGEND_WIDTH` reserving that
  space), so no pixel this deferral could affect actually exists in
  any existing hand-derived test.

  `Plot`'s own layout math -- domain/scale/tick/margin computation --
  needed zero changes to become backend-agnostic; it already only
  ever produced numbers, never called a draw primitive directly.

  Tests: `canvas_mojo/tests/test_svg.mojo` (14, see canvas_mojo/ROADMAP.md's own
  entry) cover `SvgCanvas` in isolation; five more in `test_plot.mojo`
  confirm `render_svg()` end to end for POINT/LINE/BAR/ARC and its own
  validation raise, each reusing already-hand-derived pixel math from
  the matching raster test where the coordinates are plain rounded
  integers (POINT), and cross-checked against a real `render_svg()`
  run first where they're raw, unrounded `Path`/angle floats (LINE/
  BAR/ARC) -- confirmed necessary, not just cautious: one endpoint
  came back differing from a hand-rolled Python formula by a single
  float ULP (`LinearScale.to_pixel`'s own exact operation order isn't
  identical to the simplified formula used to sanity-check it), caught
  by that cross-check before it could ship as a wrong assertion.
  `examples/scatter_svg.mojo` -- the same scatter data `examples/
  scatter.mojo` draws, through `render_svg()` instead -- viewed
  rendered (as an HTML page embedding the raw SVG markup, since
  neither the `Read` tool nor this session's own PNG-conversion
  probes render SVG directly) before considering this done; its own
  output file matched byte-for-byte against what was already visually
  confirmed.

  **Raster and SVG are both first-class, deliberately, not "SVG-first
  with raster in maintenance"** -- a real question raised (does raster
  supersampling actually hold up against SVG's own resolution
  independence, or just look close enough not to notice?) and settled
  with a direct side-by-side, not an assumption either way: the exact
  same scatter chart, once genuinely native-sized (both crisp, no
  surprise) and once *forced* to display at 2x its own file size --
  the precise "viewer shows it bigger than the source" scenario that
  started the whole `Theme.scale`/`downsample()` investigation in the
  first place. The raster PNG visibly softened (its own fixed 640x420
  pixels, stretched); the SVG did not (it re-describes every shape at
  whatever size it's asked to render, so 2x cost it nothing). Confirms
  raster crispness is only ever true *relative to one specific known
  display size* -- which this package doesn't control and can't know
  in advance -- while SVG has no such size to be wrong about, a
  structural difference no amount of supersampling closes. Both
  backends stay first-class anyway, by explicit choice made with that
  tradeoff in view, not despite it: a raster file is still the right
  answer whenever a caller's own target genuinely is a fixed, known
  size (embedding in something that doesn't support SVG, printing at
  a fixed physical size), so new features target both going forward,
  the same discipline `render_facets_svg` (below) was built under
  immediately rather than deferred.

- **`render_facets_svg()`** -- `render_facets()`'s exact SVG
  counterpart, closing the one gap left when `render_svg()` first
  landed (that gap's own entry, explaining why `render_facets()`
  originally stayed raster-only, existed in this file for all of one
  revision before being closed -- see the "both first-class" decision
  just above for why it didn't stay deferred). Both now delegate to a
  shared `_render_facets_generic[T: DrawTarget]` core -- the same
  split every other render path here uses (`_render_generic`, plus
  `render()`/`render_svg()` as its own thin per-backend wrappers).

  The blocker the original gap named -- cell-boundary math needs a
  target's own `width`/`height`, which isn't part of `DrawTarget`
  (deliberately; see canvas_mojo/ROADMAP.md's own `DrawTarget` entry for
  why a same-named trait method would collide with `Canvas.width`'s
  own field) -- turned out not to need a trait change at all:
  `_render_facets_generic` simply takes `width`/`height` as plain
  parameters, and each thin wrapper (`render_facets()`/
  `render_facets_svg()`) passes its own target's `width`/`height`
  field in, the same sentinel-resolution-at-the-wrapper-level pattern
  `render()`/`render_svg()` already established.

  One small new wrinkle handling `_TextRequest`s across multiple
  cells: each cell's own `_render_generic` call returns its own list,
  and those need combining into one list covering the whole grid --
  `text_requests.append(req.copy())` per element, not a bare `append
  (req)`, since `_TextRequest` (`Copyable`, not `ImplicitlyCopyable`)
  needs an explicit copy to move a *borrowed* loop element into a
  second list; caught immediately by the compiler's own error (which
  suggested the exact fix), not worked around blindly.

  Two new tests reuse the exact cell/pixel math `test_render_facets_
  lays_out_independent_plots_side_by_side` (the raster version) had
  already hand-solved -- confirming `render_facets_svg()` produces the
  identical two-point-in-two-cells layout, not re-derived from
  scratch -- plus a `cols <= 0` raise check. `examples/facets_svg.mojo`
  -- the same four-region data `examples/facets.mojo` draws -- viewed
  rendered before considering this done; its own per-cell coordinates
  cross-checked directly against `examples/facets.mojo`'s own already-
  confirmed raster output (same underlying `_render_generic` geometry,
  so any mismatch would have meant a real bug, not an SVG-specific
  layout difference).

- **"Phase 0" of a broader chart-type survey: donut, histogram,
  diverging bar, slope** — the first slice of a much larger plan
  (implementing the ~46 chart types the ECharts.jl gallery shows,
  sequenced by shared infrastructure rather than tackled in gallery
  order -- see the plan itself, not repeated here) chosen specifically
  because each needed at most a small, self-contained addition to
  what already existed, not new rendering machinery. Each still got
  the identical rigor -- hand-derived math, both backends, tests,
  example, viewed rendered -- as every phase before it; "small" meant
  small in *scope*, not in the bar for calling it done.

  **Donut** -- `Theme.donut_inner_radius_fraction` (default 0.0, an
  ordinary pie) switches `_render_arc`'s own wedge-drawing loop from
  `target.fill_arc_aa` to a new `target.fill_ring_sector_aa`, added to
  `DrawTarget` itself (see canvas_mojo/ROADMAP.md's own entry for the
  trait/`SvgCanvas` side of this and a real cross-compilation-context
  floating-point bug it surfaced along the way) -- a *fraction* of the
  outer radius `_render_arc` already computes, not a fixed pixel
  value, so the hole stays proportionally correct at any canvas size.
  Must be in `[0.0, 1.0)`, raises otherwise. Hand-verified on both
  backends: raster via two pixel checks (the exact center stays
  background -- the hole -- while a point on a wedge's own angular
  bisector at the ring's midpoint radius is that wedge's own color,
  confirmed via a real `render()` run before trusting the coordinate),
  SVG via the exact ring-sector path string, both against the same
  2-category `[1, 3]` data `test_render_svg_arc_mark_matches_
  confirmed_wedge_paths` already uses. `examples/donut.mojo`.

  **Histogram** -- `Plot.encode_histogram(data, bins=10)`, a new
  builder method mapping continuous `data` onto `Mark.BAR`'s own
  categorical-x/continuous-y shape by binning it first: `bins` equal-
  width half-open intervals (`[lo, hi)`, except the last, closed --
  `[lo, hi]` -- so `data`'s own maximum lands in the last bin instead
  of computing a one-past-the-end index), each bin's own count as its
  bar's value, its own range (formatted to one decimal place via
  `_format_fixed`, `LinearScale.ticks()`'s own formatter) as its
  label. Raises immediately (the binning has to happen right here to
  produce any data at all, unlike `encode()`'s own deferred length
  checks -- see that method's own docstring) on empty `data`, `bins <=
  0`, or every value identical (no span to divide). No new render
  path -- once binned, this is an entirely ordinary `Mark.BAR` plot,
  confirmed by reusing (not re-deriving) that mark's own hand-derived
  rendering tests. Bin counts hand-derived via `python3` for a 10-
  value, 5-bin dataset including one deliberately empty bin (`[5.8,
  7.4)`, count 0 -- confirming empty bins are real zero-count
  categories, not silently skipped). `examples/histogram.mojo` (30
  exam scores, a genuine bell-ish spread, not sorted or uniform data).

  **Diverging bar** -- `Theme.color_by_sign` (default `False`) plus
  `Theme.mark_color_negative` -- `_render_bar` colors each bar by
  whether its own value is negative, when the flag is on; the "bars
  extend below a zero baseline for negative values" half of a
  diverging bar chart already worked with zero changes needed (see
  `_zero_baseline_y_extent`'s own docstring) -- this is the one
  further thing a genuinely *diverging* chart adds, making the sign
  readable by color, not only by direction. An explicit opt-in flag,
  not inferred from `mark_color_negative` differing from `mark_color`
  -- no ambiguous default to guess at from color equality. `examples/
  diverging_bar.mojo` (six quarters of net change, mixed sign).

  **Slope** -- no new code at all: a slope chart *is* `Mark.LINE` with
  exactly two `(x, y)` points, a data shape already fully supported.
  `examples/slope.mojo` exists to demonstrate and view the pattern,
  not because anything needed building -- its own docstring is
  explicit about what's *not* yet true, rather than overclaiming the
  chart type is "done": the x-axis is `encode()`'s own continuous one,
  so the two positions get numeric tick labels ("0", "1"), not the
  "Before"/"After"-style category labels a slope chart's x-axis
  conventionally shows (needs categorical-x support on `Mark.LINE`,
  not built), and a real slope chart usually compares *several*
  entities' own slopes on shared axes at once, which needs the multi-
  series layering the very next phase of this same plan builds (see
  the entry below).

- **"Phase 1": `render_layers`/`render_layers_svg` — multi-series
  layering on one shared coordinate system** — the piece Phase 0's own
  slope-chart entry (above) named as needed next: several `Plot`s
  drawn together sharing *one* domain and *one* set of axes, the
  structurally different sibling to `render_facets` (each facet cell
  gets its *own* independent domain; a layered composition deliberately
  does not -- that's the entire point of overlaying series instead of
  faceting them). Built as an entirely new, standalone function
  (`_render_layers_generic[T: DrawTarget]`), not a refactor of
  `_render_generic` -- the same "small duplication over a premature
  shared abstraction" tolerance `_render_bar`'s own docstring already
  argues for, since threading a "combined domain across N plots vs. one
  plot's own domain" branch through `_render_generic`'s existing shape
  would cost more clarity than the duplication does.

  Scoped to `Mark.POINT`/`LINE`/`AREA` only -- `render_layers` raises
  if any layered plot is `Mark.BAR`/`Mark.ARC`, whose domains (band
  positions, angular sweep) aren't compatible with a shared continuous
  x/y coordinate system the way point/line/area data already is;
  layering those is real, separate, deferred work (see "Explicitly
  still open," below). Shared chrome -- background, gridlines, axis
  colors/lines, margins, font size, tick spacing -- comes from
  `plots[0]`'s own `Theme` (the first plot in the list sets the frame
  every other plot draws into); each individual plot's own
  `Theme.mark_color`/`point_radius`/`line_width` still governs only
  its own mark's appearance, each independently run through its own
  `_Scaled(p_theme)` so per-plot `Theme.scale` still works the way it
  already does everywhere else. No per-point `color`/`color_categories`/
  `size` encoding within a layered plot, and no legend (`Plot` has no
  per-series name/label field yet to build one from) -- both real,
  separate features, not small extensions of this first version (see
  below). An empty `plots` list is a silent no-op, matching
  `render_facets`'s own established convention for the same case, for
  consistency between this package's two multi-plot composition APIs.

  The combined domain is computed by concatenating every layered
  plot's own `x_data`/`y_data` and feeding the result through the exact
  same `_data_extent`/`_zero_baseline_y_extent` functions a single plot
  already uses -- `_zero_baseline_y_extent` if *any* layered plot is
  `Mark.AREA` (generalizing that mark's own existing "y-domain always
  includes zero" rule from one plot to the whole shared axis, since an
  area's baseline still needs to be visually correct even when it isn't
  the only series drawn).

  Hit, and fixed, a real Mojo compile error along the way: `for p in
  plots:` -- iterating a `List[Plot]` directly -- fails ("List
  iteration requires the element to be `Copyable`"), since `Plot` is
  deliberately `Movable` only (see `plot.mojo`'s own struct
  declaration). Indexing (`plots[i]`) compiles fine; only *iteration*
  hits this. Fixed by rewriting every loop over `plots` (validation,
  domain accumulation, drawing) to the index-based `for i in
  range(len(plots)): ... plots[i] ...` form `render_facets` had already
  established for the identical reason.

  Hand-verified on both backends against the same two-series data (a
  `Mark.LINE` plot and a `Mark.POINT` plot sharing one x=[0,10],
  y=[0,10]-ish domain): raster confirmed a point at data (5,5) lands at
  the exact same hand-derived pixel `(220, 135)` the single-plot point
  test already established (the shared-domain math reduces to the
  identical formula once there's only one series' own extent to
  consider), colored that plot's own `mark_color` and not the other
  plot's; SVG confirmed the line's own path string exactly,
  `M74.545,239.545 L365.455,30.455` -- both cross-checked via live
  scratchpad probes before being trusted in a test, not hand-typed from
  the formula alone. Two more tests lock in the `Mark.BAR` raise and
  the empty-list no-op. `examples/layers.mojo` (a revenue line
  overlaid with forecast-checkpoint points, six months, sharing one
  axis) viewed as a rendered PNG before considering this done.

- **"Phase 2a": lollipop, waterfall, box -- three more categorical-x-
  axis marks, sharing one axis-frame core** -- the first slice of
  "Phase 2" (new Cartesian mark shapes) from the broader chart-type
  survey, deliberately split from the rest of Phase 2 (candlestick,
  bullet, gantt/spanchart) since these three build on `Mark.BAR`'s own
  existing categorical-x-axis machinery directly, while the rest each
  need their own new mark shape or (`gantt`) a whole new horizontal-bar
  orientation `Mark.BAR` doesn't have.

  **`_draw_categorical_axis_frame`** -- the one real architectural
  addition this slice needed: `_render_bar`'s own axis-frame logic
  (dynamic left margin, `OrdinalScale`, gridlines, axis lines, every
  tick+label) extracted into its own function once a *third*
  categorical mark needed it verbatim, shared now by all four
  (`Mark.BAR`/`LOLLIPOP`/`WATERFALL`/`BOX`) -- see that function's own
  docstring for the full reasoning (why two call sites sharing a little
  duplication, this codebase's own established tolerance, stopped
  applying once a fourth near-identical ~130-line copy was on the
  table) and the one real, harmless behavioral difference from `_render_
  bar`'s original self-contained body (the per-category tick+label loop
  and the per-category mark-drawing loop became two passes instead of
  one combined loop -- confirmed harmless directly, not just by
  construction: every pre-existing `Mark.BAR` test kept passing
  unchanged). `_render_bar` itself was refactored onto this shared core
  too, not left as a fifth independent copy alongside it.

  One real Mojo ownership error hit building this, not a logic bug:
  moving `_CategoricalFrame`'s own `text_requests` field out via `frame.
  text_requests^` failed twice, with two different compiler messages
  depending on *when* it was tried -- immediately after building `frame`
  ("value 'frame.text_requests' cannot be consumed, because 'frame' is
  used later," since the per-category loop right after still reads
  `frame.x_scale`/`y_scale`/`sc`), and even as the function's own last
  statement ("field 'frame.text_requests' destroyed out of the middle of
  a value, preventing the overall value from being destroyed" -- Mojo
  doesn't support partially moving one field out of a still-otherwise-
  intact struct at all, not even as its final use). Fixed with a `.copy()`
  instead of a `^` transfer at the return -- `_TextRequest` is `Copyable`
  (see its own docstring), so a small `List` copy there is a cheap,
  simple trade against hand-unpacking every field `_CategoricalFrame`
  carries just to satisfy the checker.

  **Lollipop** -- `Mark.LOLLIPOP` reuses `Mark.BAR`'s own `encode_
  categorical()` data shape completely unchanged (a lollipop and a bar
  chart differ only in *how* a category's magnitude is drawn, not what
  the data means): a stem (`stroke_path_aa`, `Theme.line_width`,
  matching `Mark.LINE`'s own convention) from the zero baseline to the
  value, capped with a point (`fill_circle_aa`, `Theme.point_radius`,
  matching `Mark.POINT`'s own). `examples/lollipop.mojo` (ten countries'
  own GDP, more categories than any other categorical example so far --
  a lollipop chart's own thin stems read better than a bar chart's full
  width would at this count).

  **Waterfall** -- `Plot.encode_waterfall(categories, deltas)`, a new
  data shape (a category + a *signed delta*, not a plain value): each
  bar floats from the running total *before* it to the running total
  *after* it, computed immediately as a running cumulative sum starting
  from 0.0 (no reason to raise the way `encode_histogram()`'s binning
  does -- a running sum has no degenerate-span case). `_render_waterfall`
  draws each floating bar colored by its own delta's sign
  *unconditionally* (`theme.mark_color_negative`/`mark_color`, not
  gated by `Theme.color_by_sign` the way `Mark.BAR`'s diverging coloring
  is -- sign coloring *is* what a waterfall conventionally shows, not an
  opt-in extra), plus a thin connector line between consecutive bars at
  the pixel height where one bar's own running total hands off to the
  next. That connector's own color went through one real, visually-
  caught revision: `theme.gridline_color` first (reusing an existing
  field, seemed reasonable on paper), but viewing `examples/
  waterfall.mojo`'s own rendered output showed it visually
  indistinguishable from the y-axis's own gridlines -- switched to
  `theme.axis_color` instead, clearly visible against both bars and
  background, confirmed by re-viewing the same example. No "total" bar
  support (a real waterfall chart convention: a wider bar showing the
  running total itself at the start/end or at intermediate checkpoints)
  -- `encode_waterfall()` is pure deltas only; a zero-delta bar wouldn't
  draw anything, so `examples/waterfall.mojo`'s own docstring says this
  explicitly rather than working around it with a fake trailing bar.

  **Box** -- `Plot.encode_boxplot(categories, values: List[List[Float64]])`,
  the first `encode_*` whose per-category "value" is a whole
  distribution, not one number: computes each category's own five-
  number summary immediately (not deferred to render() time, the same
  "can't produce a coherent result at all otherwise" reasoning `encode_
  histogram()`'s binning already established) via the new `_box_stats`/
  `_percentile` helpers -- quartiles by linear interpolation (`numpy.
  percentile`'s own default method, `"linear"`, so results match what a
  caller could independently verify), whiskers as the most extreme
  value still within the conventional 1.5*IQR fence (not the raw min/
  max -- separating "whisker" from "outlier" is the entire point), every
  value beyond that fence as its own outlier, tagged with which category
  it belongs to. Raises immediately on a mismatched `categories`/`values`
  length or any category with zero values (quartiles are undefined for
  an empty distribution, no sensible fallback the way an empty histogram
  bin's zero count is).

  `_render_box`'s own y-domain is the one real domain-rule difference
  among these four marks: `_data_extent` (padded, not forced through
  zero) over every whisker and outlier value actually drawn -- unlike
  `Mark.BAR`/`LOLLIPOP`/`WATERFALL`, whose magnitude-from-a-baseline
  meaning always needs zero in view, a box plot shows a distribution's
  own spread, which has no inherent reason to include zero (this is
  exactly why `_draw_categorical_axis_frame` takes `y_scale` as an
  already-decided parameter rather than computing it itself). Draws,
  per category: two whiskers with small end caps, the box itself over
  them, a median line on top of the box fill, then every outlier in one
  final pass *after* every category's own box/whiskers (so one
  category's outlier is never occluded by a neighboring category's own
  box).

  All three hand-derived via Python (quartiles/whiskers/outliers
  independently reimplemented there, not just re-run through the Mojo
  code, before trusting them) and cross-checked against real `render()`/
  `render_svg()` runs before being trusted in a test -- 14 new tests
  total (raster + SVG + a raise case for each of the three, plus one
  more confirming `render_layers()`'s existing POINT/LINE/AREA-only
  allow-list correctly rejects `Mark.LOLLIPOP` too, not just `Mark.BAR`,
  without needing its own check updated). `examples/lollipop.mojo`,
  `waterfall.mojo`, `box.mojo` -- three new example files following the
  established "one file, both backends" convention -- each viewed as a
  rendered PNG before considering this done.

- **"Phase 2b" (part 1): candlestick** — the first of three marks split
  out from "Phase 2a" (see Done, above) because each needs its own new
  shape rather than building on `Mark.BAR`'s existing data directly.
  `Plot.encode_candlestick(categories, open, high, low, close)`, a new
  data shape (a category plus *four* values, not `encode_categorical()`'s
  single value) -- like `encode_categorical()`/`encode_waterfall()`,
  nothing needs computing up front (every value is drawn exactly as
  given, no summary statistic or binning), so length checking stays
  deferred to `render()` time rather than raised immediately the way
  `encode_histogram()`/`encode_boxplot()`'s own binning/statistics have
  to be.

  `_render_candlestick` reuses `_draw_categorical_axis_frame` (the same
  shared axis-frame core `BAR`/`LOLLIPOP`/`WATERFALL`/`BOX` already use)
  with a `_data_extent` y-domain over every open/high/low/close value
  actually drawn -- *not* forced through a zero baseline, the same
  reasoning `Mark.BOX` already established: a candlestick chart's whole
  point is showing fine detail in a price range that's typically nowhere
  near zero, so forcing zero into view would flatten exactly the detail
  the chart exists to show. Draws, per category, back to front (the same
  "whisker under the box" order `_render_box` already established, so a
  short body still reads as attached to its own wick rather than as two
  disconnected shapes): a thin wick (`draw_line_aa`, `theme.axis_color`
  -- matching `Mark.BOX`'s own whisker color) from `high` to `low`, then
  the body (`fill_rect`, full band width, matching `Mark.BAR`/`BOX`'s own
  "no extra narrowing" choice) from `open` to `close`, colored by
  `close >= open`: `theme.mark_color` (up) or `theme.mark_color_negative`
  (down) -- the *same* two fields `Mark.WATERFALL` already reuses for its
  own unconditional sign coloring, not new dedicated bullish/bearish
  Theme fields, since a candlestick's sign coloring *is* the chart the
  same way a waterfall's is (see `Theme`'s own docstring, updated to
  name both marks together). A doji (`open == close` exactly) floors its
  own body height at 1px rather than left to `fill_rect`'s own zero-size
  no-op (see that function's own tests) -- a real, if rare, input a
  price series can produce, and a real candlestick chart shows it as a
  thin flat body, not an invisible one.

  Hand-derived via `python3` (the same 2-category `OrdinalScale`/
  `LinearScale` methodology `test_render_boxplot_matches_hand_derived_
  box_whiskers_and_outlier` already used, reusing that test's own band
  math since both use an identical 2-category domain over the same
  [60,380] range -- only the y-domain and per-category shape differ):
  one closed-up and one closed-down category, each pixel (wick extent,
  body rect, both colors) confirmed against a real `render()`/
  `render_svg()` run before being trusted in a test. Six new tests
  (raster + SVG hand-derived matches, a categories-vs-OHLC-length raise,
  an OHLC-columns-disagree-with-each-other raise, plus one more
  confirming `render_layers()`'s existing `POINT`/`LINE`/`AREA`-only
  allow-list correctly rejects `Mark.CANDLESTICK` too, the same
  "checked again for each new mark, not just assumed from reading the
  condition" discipline `Mark.LOLLIPOP`'s own equivalent test already
  established). `examples/candlestick.mojo` -- eight trading days of a
  single stock, a realistic mix of up/down days including one wide-range
  and one narrow-range day -- viewed as a rendered PNG before considering
  this done.

- **"Phase 2b" (part 2): bullet** — Stephen Few's bullet-chart design,
  the second of the three marks split out from "Phase 2a" (see
  candlestick's own entry, just above, for part 1). `Plot.encode_bullet
  (categories, measures, targets, ranges)`, the richest data shape any
  `encode_*` here takes -- a category plus a measure, a target, and a
  whole *list* of ascending qualitative-range thresholds per category
  (e.g. `[50.0, 75.0, 100.0]` for poor/satisfactory/good). Like `encode_
  candlestick()`, length/shape checking (`categories`/`measures`/
  `targets`/`ranges` all the same length, plus each category's own
  `ranges` entry non-empty and non-decreasing -- the band-stacking math
  depends on that order) is deferred to `render()` time rather than
  raised immediately, the same "nothing needs computing up front"
  reasoning every other non-statistical `encode_*` here already follows.

  `_render_bullet` reuses `_draw_categorical_axis_frame` (the same
  shared axis-frame core `BAR`/`LOLLIPOP`/`WATERFALL`/`BOX`/
  `CANDLESTICK` all use) with a `_zero_baseline_y_extent` y-domain --
  *unlike* `BOX`/`CANDLESTICK`'s own padded-around-the-data domains, a
  bullet chart's whole premise is progress toward a goal from zero, the
  same "magnitude from a baseline" meaning `BAR` already forces into
  view, generalized here to span every value actually drawn per
  category (`0.0`, the top of its own `ranges`, its `measure`, and its
  `target` -- the same "domain guaranteed to fit everything drawn"
  reasoning `WATERFALL`/`BOX` already established, since a measure or
  target can legitimately fall outside the qualitative ranges).

  Draws, per category, back to front (context underneath, headline
  value over it, reference mark on top of everything -- a direct
  generalization of `BOX`'s own whisker-then-box-then-median order):
  every qualitative range band stacked from `0.0` up through each
  threshold in turn (`fill_rect`, full band width like `BAR`/`BOX`),
  shaded via a small `dataviz_mojo.color_scale.ColorScale` built once from
  two new `Theme` fields (`bullet_range_color_light`/
  `bullet_range_color_dark`, default grayscale -- Few's own convention,
  and dedicated fields rather than `mark_color`-derived shades so a
  background band reads as neutral context, not competing with the
  measure bar for attention) -- the *same* stop-interpolation machinery
  `Plot.encode(color=...)`'s own continuous channel already uses,
  projecting each band's index fraction onto `[0, 1]` instead of a data
  value; then the measure bar (`fill_rect`, `theme.mark_color`, a new
  `_BULLET_MEASURE_WIDTH_FRACTION` (0.35) of the full band width and
  centered within it -- narrower on purpose, a fixed module constant
  matching `_TICK_LENGTH`'s own "nothing concrete has needed this
  configurable yet" reasoning, not a `Theme` field); then the target
  tick (`draw_line_aa`, `theme.axis_color`, full band width, exactly
  `BOX`'s own median-line convention), drawn last so it's never
  obscured.

  One deliberate, documented departure from `CANDLESTICK`/`WATERFALL`'s
  own precedent: the measure bar is *never* colored by sign -- no
  `mark_color_negative` involved at all. A bullet chart's whole
  comparison is measure-against-target-and-ranges, conveyed by
  *position*, not by the bar's own color; Few's original design keeps
  it one solid, neutral color for exactly that reason, and this
  package follows that rather than reusing the sign-coloring
  convention just because the fields already exist elsewhere. A second
  departure from `CANDLESTICK`'s own doji handling: a `measure` of
  exactly `0.0` draws a genuine zero-height (invisible) bar, not
  floored to 1px -- a doji needs a visible mark because it's real,
  informative market data at a specific price; a zero measure means
  literally "no progress yet," which an absent bar already represents
  correctly, so flooring it would misrepresent the data instead of
  clarifying it.

  Hand-derived via `python3` (the same 2-category `OrdinalScale`/
  `LinearScale` methodology `CANDLESTICK`'s own tests already used,
  reusing that test's identical band math -- only the y-domain and
  per-category shape differ, plus the grayscale interpolation itself
  hand-computed and cross-checked: `t=0.5` between `(224,224,224)` and
  `(120,120,120)` lands exactly on `(172,172,172)`, no rounding
  ambiguity since all three channels are equal). Seven new tests
  (raster + SVG hand-derived matches covering all three bands plus the
  measure bar and target tick, three raise cases -- mismatched column
  lengths, an empty `ranges` entry, non-ascending thresholds -- plus one
  more confirming `render_layers()`'s existing allow-list correctly
  rejects `Mark.BULLET` too). `examples/bullet.mojo` -- four quarterly
  KPIs on a dashboard, a realistic mix of beat-target and missed-target
  results -- viewed as a rendered PNG before considering this done.

- **"Phase 2b" (part 3, final): gantt/spanchart** — the last of "Phase
  2b" (see candlestick's and bullet's own entries, just above, for parts
  1-2), and the biggest structural lift of the three: the first mark
  whose categories run along a *horizontal* axis. `Plot.encode_gantt
  (categories, start, end)` -- a category plus a numeric range, no
  dedicated `Date`/`Time` type (this package has none anywhere; see that
  method's own docstring for why a project schedule's "dates" are just
  `Float64`s here the same as every other numeric column, which is also
  why this one mark doubles as a generic "span chart," not something
  scheduling-specific). Length checking deferred to `render()` time, the
  same as every other categorical `encode_*`; `start[i] > end[i]` isn't
  rejected either -- `_render_gantt` draws from `min`/`max`, the same
  tolerance `Mark.CANDLESTICK`'s own open/close handling already has.

  `_draw_horizontal_categorical_axis_frame` (`plot.mojo`) is the real
  new piece: the mirror image of `_draw_categorical_axis_frame`, with
  `x`/`y`'s roles fully swapped -- a continuous `LinearScale` runs
  left-to-right along the bottom, an `OrdinalScale` runs top-to-bottom
  along the left (category index 0 at the *top*, confirmed directly via
  a hand-derived first-vs-second-category pixel check, not assumed --
  the natural "first task listed first" reading order a real project
  schedule wants). Deliberately a *separate* function from the vertical
  frame, not a generalized, orientation-flagged version of it -- with
  exactly one caller so far, the same "a little duplication over a
  premature shared abstraction" tolerance this file has applied
  consistently since `_render_bar`'s own docstring first stated it;
  threading an orientation branch through nearly every line (which
  scale is which type, which axis reverses, which margin grows
  dynamically) would cost more clarity than a second, structurally
  similar function does. The one real shape difference in its own
  dynamic-margin computation: it measures the category *names*
  themselves directly (`_max_label_width(categories, ...)`), not a
  scale's own formatted tick labels the way the vertical frame's
  `y_scale.ticks().labels()` does -- there's no numeric-tick step here,
  `OrdinalScale`'s domain already *is* the label text.

  `_render_gantt` itself draws one floating horizontal bar per category
  (`fill_rect`, full row height, `theme.mark_color` -- no sign to color
  by, unlike `WATERFALL`/`CANDLESTICK`; a schedule span has no positive/
  negative reading), x-domain via `_data_extent` (padded, not forced
  through zero) over every `start`/`end` value actually drawn. That
  domain choice is also where this entry ties off the *general*
  question this package's whole categorical-mark lineup raises: `BAR`/
  `LOLLIPOP`/`WATERFALL`/`BULLET` all encode *magnitude from a
  baseline* (how big, how much progress) and so force zero into view;
  `BOX`/`CANDLESTICK`/`GANTT` all encode *where something falls within a
  range* (a distribution's spread, a trading day's price band, a task's
  schedule window) and don't, since zero is usually irrelevant there and
  forcing it in would flatten exactly the detail each of those charts
  exists to show -- not three independent decisions, one recurring
  principle applied three times. A zero-length span (`start[i] ==
  end[i]`, a real milestone/deadline, not an absent value) floors to
  1px, the same reasoning -- and the same departure from `Mark.BULLET`'s
  own zero-measure handling -- `Mark.CANDLESTICK`'s doji case already
  established. No dependency-arrow drawing between related bars (a real
  gantt-chart convention) -- out of scope for this first version, the
  same way `Mark.WATERFALL`'s first version shipped without "total"
  bars: `encode_gantt()`'s data shape has no notion of task dependency
  to begin with, and it wasn't what this ROADMAP item asked for (a
  horizontal-bar orientation, which this provides).

  Hand-derived via `python3` (`OrdinalScale`'s own band formula for the
  now-vertical categorical axis, `LinearScale`'s own slope/intercept for
  the now-horizontal continuous one -- both independently re-derived,
  not assumed to carry over unchanged just because the axes swapped
  roles) using short single-letter category names ("A"/"B") so the
  dynamic left margin stays at `Theme`'s own default, the same
  short-label convention `test_render_left_margin_unchanged_for_short_
  y_axis_labels` already established, sidestepping real font-metric
  dependence in the hand-derivation itself. Seven new tests (raster +
  SVG hand-derived bar-rectangle matches, an explicit zero-length-span-
  floors-to-1px check, a categories/start/end length-mismatch raise, an
  empty-data no-op, plus one more confirming `render_layers()`'s
  existing allow-list correctly rejects `Mark.GANTT` too). `examples/
  gantt.mojo` -- a five-task project schedule in day-numbers, with an
  intentionally overlapping pair (Testing starting before Development
  finishes) -- viewed as a rendered PNG before considering this done.

  This closes out "Phase 2b," and with it the ~46-chart-type survey's
  originally-scoped phases (see "Phase 0"'s own entry for how this
  whole multi-session effort was sequenced by shared infrastructure
  rather than gallery order) -- what's left of the original survey is
  whatever wasn't explicitly phased in yet, not tracked as a single
  open item here; see "Explicitly still open," below, for the concrete,
  named gaps this file already knows about instead.

- **`Theme.line_smoothing`: curved `Mark.LINE`** — the first feature
  added outside the chart-type-survey phases above, on direct request:
  an optional Catmull-Rom-derived spline through a line plot's own data
  points, instead of always the plain straight point-to-point segments
  `Mark.LINE` has drawn since this package's very first vertical slice.
  A `Theme` field (default `0.0`, unchanged straight segments), not a
  `Plot.mark_line()` parameter -- every other `mark_*()` builder here is
  zero-argument, and *how* a line looks (vs. what its data means) is
  exactly the category of decision this package's own Theme already
  owns (`donut_inner_radius_fraction`, `color_by_sign`, `bullet_range_
  color_light`/`dark` are all the identical "per-mark-type visual knob
  lives on Theme" pattern, not a new one invented for this).

  `_build_line_path` (`plot.mojo`) is the new piece `Mark.LINE`'s own
  render branch now calls instead of building its `Path` inline: `0.0`
  takes an explicit early branch (plain `move_to` + one `line_to` per
  point, *not* a degenerate curve formula that happens to look
  straight) so the default stays byte-for-byte identical to every
  render from before this feature existed -- confirmed directly, not
  assumed: a whole-canvas pixel-for-pixel comparison between `Theme`'s
  bare default and an explicit `Theme(line_smoothing=0.0)`, the same
  "purely additive" bar `Theme.scale`'s own equivalent test already set.
  The explicit-branch choice (over relying on the Bezier math itself
  reducing to a straight line at `smoothing=0.0`) was deliberate, not
  extra caution for its own sake: a flattened cubic Bezier samples its
  16 fixed steps at even *parameter* spacing, not even *pixel* spacing,
  so even a geometrically-straight cubic can flatten into a visibly
  different intermediate point set than a single `line_to` -- not worth
  the risk when a plain branch is both simpler and provably identical.

  `smoothing > 0.0` builds one cubic Bezier per segment via the
  standard "uniform Catmull-Rom to Bezier" conversion (control point =
  endpoint +/- (next-point minus previous-point)/6, endpoints clamped to
  a one-sided tangent) -- `smoothing` scales each tangent's own length
  directly (not a blend between two separately-computed control-point
  sets), so `1.0` is the textbook Catmull-Rom curve and, say, `0.5` bows
  exactly half as far from the straight path at the same point. Values
  outside `[0.0, 1.0]` raise (checked in `Mark.LINE`'s own render
  branch, the same "validated at render() time, since Theme is only
  fully known there" pattern `donut_inner_radius_fraction` already
  established) -- an overshoot tension this package assigns no meaning
  to, rather than silently rendering an unbounded, likely self-
  intersecting curve.

  Scoped to `Mark.LINE` only, not `Mark.AREA` too, even though `AREA`
  shares `LINE`'s own point-to-point data and a near-identical path-
  building loop today -- matches exactly what was asked for; extending
  `_build_line_path` (or a shared variant of it) to `AREA`'s own fill
  boundary is a real, small, separate follow-up if wanted, not done
  speculatively here.

  Every control-point coordinate hand-derived via `python3`, independently
  reimplementing the exact tangent formula (not just re-running the Mojo
  code) with the identical operation order so the resulting `Float64`s
  match bit-for-bit, not just approximately -- both a direct unit test on
  `_build_line_path` itself (4 points with a real bend at each interior
  point, `smoothing=1.0`, every one of the two cubic segments' six
  control-point coordinates asserted exactly) and a full `render_svg()`
  run (a 3-point "peak" line, `smoothing=1.0`, the exact two-segment `d`
  attribute confirmed). The raster side adds one more, genuinely
  empirical check beyond "some curve command got emitted": the straight
  line's own first-segment midpoint (hand-solved from `LinearScale`'s
  slope/intercept formula) still has real ink under `smoothing=0.0` but
  is plain background under `smoothing=1.0` -- confirmed via two real
  `render()` runs, not assumed from the control-point math alone, since
  a cubic Bezier's own parametrization bows a curve's *midpoint* well
  away from the straight-line midpoint at the same `t` (the same
  "Bezier's `t` isn't evenly spaced along the curve" fact that motivated
  the explicit `smoothing <= 0.0` branch above, now put to use as a
  positive test signal instead of a risk to avoid). `examples/
  line_smoothing.mojo` -- one deliberately jagged eight-point series,
  rendered twice side by side via `render_facets()`/`render_facets_svg()`
  (straight on the left, fully smoothed on the right) so the difference
  is a direct visual comparison, not two files a viewer has to hold in
  memory against each other -- viewed as a rendered PNG before
  considering this done.

  **Extended to `Mark.AREA`, 2026-08-16** (was scoped to `Mark.LINE`
  only at first -- see "Explicitly still open," this entry's own
  original home before this): `Mark.AREA`'s own fill-region path now
  calls the exact same `_build_line_path` `Mark.LINE` does for its own
  *top* edge (through the data points) -- the two `line_to()`s down
  to/along the zero baseline plus `close()` stay straight regardless
  of `smoothing`, since baseline is a fixed reference line, not data,
  with nothing to curve through. Three new tests (an exact SVG-string
  match for the smoothed top edge closed with straight baseline edges,
  a purely-additive default-matches-unset-smoothing pixel-for-pixel
  comparison, and the `[0.0, 1.0]` range raise) plus `examples/
  area_smoothing.mojo` (the identical eight-point series `examples/
  line_smoothing.mojo` uses, same side-by-side-via-`render_facets()`
  layout) -- viewed as a rendered PNG before considering this done.

- **`Plot.labels()`: chart title + axis titles** -- `.labels(title=
  "...", x_title="...", y_title="...")`, three independent, optional
  captions (all default `""`, "not set"), not data (see that method's
  own docstring for why they're named `x_title`/`y_title`, not `x`/`y`,
  right next to `.encode(x=..., y=...)`'s own completely different
  meaning for those letters).

  The real design decision: `_apply_labels` (plot.mojo) runs *once*,
  inside `render()`/`render_svg()` themselves, *before* handing off to
  `_render_generic` -- not threaded through `_render_generic`, `_draw_
  categorical_axis_frame`, `_draw_horizontal_categorical_axis_frame`,
  or any mark-specific `_render_*` function, none of which know titles
  exist. Titles are pure outer-rect geometry (how much smaller a
  rectangle to hand downstream), so shrinking that rectangle once,
  outside every render path, gets the same effect as threading title
  state through all of them, for a small fraction of the surface area
  -- the same "a little duplication/a small wrapper over threading a
  flag through many functions" reasoning `_render_bar`'s own docstring
  already established, applied one level higher up the call chain than
  it's been applied before. `Theme.title_font_size` (default 18.0, a
  heading) and `axis_title_font_size` (14.0, between that and
  `font_size`'s own 12.0 for tick/legend labels) are the two new sizes
  this needed, both scaled by `Theme.scale` through `_Scaled` like
  every other pixel-sized quantity.

  The y-axis title is the interesting piece: rotated -90 degrees (reads
  bottom-to-top, the standard convention) via `_TextRequest`'s own new
  `rotation` field. The raster backend already supported this
  (`canvas_mojo.text.draw_text`'s own long-standing `rotation` param) --
  the SVG backend didn't, so `SvgCanvas.draw_text` gained a `rotation`
  parameter too (a `transform="rotate(<deg> <x> <y>)"` attribute,
  omitted entirely at the default `0.0` so every pre-existing call/
  output stays byte-for-byte unchanged), landed and pushed as its own
  commit in the now-standalone `canvas_mojo` repo before this feature
  used it. No sign flip converting radians to degrees for the rotation
  *direction* itself: confirmed directly via a real rendered raster
  probe (not just argued from "both Cairo and SVG put y down") that
  `rotation=-pi/2` gives the intended bottom-to-top reading, *before*
  trusting that sign in the SVG hand-derived test.

  `Mark.ARC` has no x/y axes at all, so `x_title`/`y_title` raise at
  render() time if set on an `Mark.ARC` plot (`title` alone is fine
  there -- a pie chart can absolutely have a heading) -- the same
  "raise on a setting that can't apply" rule `Plot.encode`'s own color/
  size-on-a-non-`POINT`-mark check already follows.

  Title/`x_title` center over the *outer* bounds `render()`/`render_
  svg()` were called with, not the mark-specific inner plot rectangle
  (dynamic left margin, optional legend column) computed deeper inside
  -- that inner rectangle isn't known until that deeper call actually
  runs, and isn't returned back up. A known, deliberate v1
  simplification (see "Explicitly still open," below), not an
  oversight.

  Hand-derived via `python3` (re-solving `_apply_labels`'s own margin
  math and every downstream `LinearScale` coordinate against the
  *shrunk* inner rect, not the original hand-derived-elsewhere-in-this-
  file plot-area numbers, since the outer bounds genuinely changed).
  Six new tests: an exact SVG-string match for all three captions at
  once (title unrotated, x_title unrotated, y_title's own hand-derived
  `rotate(-90.000 ...)`, plus the LINE mark's own re-solved endpoints),
  a purely-additive default-matches-unset-labels pixel-for-pixel
  comparison, a raster ink-presence check in the title's own reserved
  band, and the `Mark.ARC` raise (both directions, plus confirming
  `title` alone does *not* raise there). `examples/titles.mojo` -- a
  quarterly-revenue bar chart, all three captions set at once, both
  backends -- viewed as a rendered PNG before considering this done.

- **`Mark.GROUPED_BAR`: grouped bar chart** — `Plot.mark_grouped_bar()
  .encode_grouped_bar(categories, series_names, values)`, several bars
  side by side per category instead of `Mark.BAR`'s one. `values` is a
  `List[List[Float64]]` indexed `[series][category]` (`values[j][i]` is
  series `j`'s own value for `categories[i]`) -- the same "outer list
  indexes the thing being repeated, inner list indexes categories"
  shape `encode_boxplot()` already established for a *distribution* per
  category, here a *series* per category instead. Length checking
  (`series_names`/`values` the same length, every `values[j]` the same
  length as `categories`) deferred to `render()` time, the same as
  every other categorical `encode_*` here.

  Shares `_draw_categorical_axis_frame` with `Mark.BAR`/`LOLLIPOP`/
  `WATERFALL`/`BOX`/`CANDLESTICK`/`BULLET` unchanged -- the only new
  layout piece is a legend column, reserved by shrinking the *outer*
  `ox1` passed into that shared function (`ox1 - legend_reserve`)
  rather than threading a new parameter through it, the exact "shrink
  the rect from outside, don't touch the shared core" pattern `Plot.
  labels()`'s own `_apply_labels` already established for title/axis-
  title margins -- confirms that pattern generalizes to a second,
  unrelated feature needing extra outer margin, not a one-off. `Theme.
  show_legend` gates it, same flag `Mark.POINT`'s own categorical-color
  legend uses.

  Each category's own band subdivides into `len(series_names)` equal
  sub-bars via `default_categorical_palette()` (cycled `j % len
  (palette)`, `Mark.POINT`'s/`Mark.ARC`'s own convention) -- sub-bar
  edges computed as *rounded boundaries* (`round(band_start + j *
  sub_width)` for `len(series_names) + 1` boundary points), not
  independently rounded widths, the standard fencepost-safe way to
  subdivide a span into pixel segments with no 1px gaps or overlaps
  between adjacent sub-bars. No sign-coloring (unlike `Mark.BAR`'s own
  `Theme.color_by_sign`) -- a grouped bar chart's whole point is
  telling series apart by color, not sign.

  Hand-derived via `python3` (`OrdinalScale`'s own band formula re-
  solved against the *legend-shrunk* range, not `Mark.BAR`'s own plain
  full-width one, plus `LinearScale`'s slope/intercept for each sub-
  bar's height) -- caught its own hand-derivation bug directly, not
  just the implementation's: a first pass mislabeled which value
  belonged to which (category, series) pair (crossing `North`'s and
  `South`'s own values for one category), confirmed and fixed by
  comparing against a real `render_svg()` run's actual output before
  trusting the corrected numbers in the test. Seven new tests (raster
  + SVG hand-derived rectangle matches including the legend's own two
  swatches, an inter-category-gap background check, an empty-categories
  no-op, both length-mismatch raises, and `render_layers`'s existing
  `Mark.POINT`/`LINE`/`AREA`-only allow-list confirmed to reject this
  mark too). `examples/grouped_bar.mojo` -- three regions' quarterly
  revenue, composed with `Plot.labels()` in the same chart (confirming
  the two features' own independent outer-rect-shrinking compose
  cleanly, not just each in isolation) -- viewed as a rendered PNG
  before considering this done.

- **`Mark.STACKED_BAR`: stacked bar chart** — `Plot.mark_stacked_bar()`,
  reusing `encode_grouped_bar()`'s exact data shape unchanged -- no new
  encode method, the same relationship `Mark.LOLLIPOP` already has to
  `Mark.BAR`'s own `encode_categorical()` (identical data, purely a
  rendering difference). Each category's own series stack as segments
  on top of each other instead of `Mark.GROUPED_BAR`'s side-by-side
  sub-bars -- full band width per segment (`Mark.BAR`'s own
  convention), not `bandwidth / len(series_names)`.

  Mixed-sign values stack in *two* independent running totals per
  category, not one: a non-negative value's own segment builds upward
  from that category's own running positive total; a negative value's
  own segment builds downward from the running negative total,
  independently -- the standard convention for a mixed-sign stack
  (a negative value part-way through a naive single running sum would
  visually slide every segment above it back down, nonsensical for a
  composition chart). The y-domain (`_zero_baseline_y_extent`) is
  computed over each category's own *final* positive/negative totals in
  a first pass; the drawing pass recomputes the same running totals
  again rather than storing them, cheap at the series counts this
  handles.

  The one geometry question `Mark.GROUPED_BAR`'s own sub-bar division
  needed an explicit rounded-boundary trick for turned out to need
  nothing extra here: a segment's own top and the segment above it's
  own bottom are always the *identical* running-total `Float64`
  (carried over exactly, not recomputed from two different band-
  relative offsets), so `_axis_pixel` -- a pure function of its input
  -- rounds both to the same pixel automatically. Confirmed directly,
  not just argued, by a dedicated mixed-sign test rather than assumed
  to follow from the all-positive case.

  Same legend as `Mark.GROUPED_BAR` (series name -> color, same outer-
  rect-shrinking reservation), deliberately still duplicated between
  the two `_render_*` functions rather than factored out -- two call
  sites sharing a little duplication remains this codebase's own
  tolerance, extract once a third mark needs the identical legend
  logic. No sign-coloring, same reasoning `Mark.GROUPED_BAR` already
  gives: telling series apart by color *is* the chart, not an optional
  extra layered on top of a magnitude-from-baseline reading.

  Hand-derived via `python3`, two scenarios: the same all-positive
  North/South/A/B data `Mark.GROUPED_BAR`'s own test reuses (confirming
  the totals/segment math independently of that mark's own already-
  proven band math), plus a dedicated single-category mixed-sign case
  (North=10, South=-5) exercising the two-running-totals logic no
  all-positive test can reach. Seven new tests (raster + SVG hand-
  derived segment matches including both legend swatches, the mixed-
  sign SVG test, an empty-categories no-op, both length-mismatch
  raises reusing `encode_grouped_bar()`'s own validation, and
  `render_layers`'s existing allow-list confirmed to reject this mark
  too) -- all passing on the first run. `examples/stacked_bar.mojo` --
  the exact same three-region quarterly-revenue data `examples/
  grouped_bar.mojo` uses, so the two examples read as a direct grouped-
  vs-stacked comparison of identical numbers -- viewed as a rendered
  PNG before considering this done.

- **Waterfall "total" bars** — `encode_waterfall()`'s own `is_total:
  List[Bool] = List[Bool]()` (default empty -- no row is a total,
  `Mark.WATERFALL`'s original delta-only behavior, unchanged): a total
  row's own `deltas[i]` still adds to the running sum exactly like any
  other row (so a starting-balance total is just the first row, marked
  total, with `deltas[0]` set to the starting value; an ending-balance
  total is the last row, marked total, with `deltas[i]` left at `0.0`)
  -- the only difference is *display*: a total row draws from `0` up to
  the running total *after* its own delta, not floating from before to
  after the way a plain delta row does. Colored `Theme.waterfall_
  total_color` (a new, third, neutral-gray color -- distinct from the
  rising/falling pair, since a total isn't "a big increase/decrease,"
  it's a different kind of thing on the same chart) and drawn full band
  width, vs. a new `_WATERFALL_DELTA_WIDTH_FRACTION` (0.6, centered) for
  plain delta rows -- but *only once a plot actually uses at least one
  total row* (`plot._waterfall_is_total` non-empty); with `is_total`
  never passed at all, every bar stays full band width, unchanged,
  purely additive.

  Found and fixed two real bugs mid-implementation, both caught by a
  pre-existing test failing against real output, not assumed correct:
  (1) the first version narrowed *every* delta bar unconditionally,
  breaking the pre-existing no-`is_total` case's own already-passing
  test -- fixed by gating the narrow/full distinction on whether the
  plot uses total rows at all, not on a given row's own status alone;
  (2) the connector-line pass, once bars could have unequal actual
  widths, first tried reusing each bar's own precomputed `bar_x +
  bar_width` for every case, which reintroduced a classic "sum of two
  independently-rounded values != rounding of the sum" 1px drift for
  the *original* full-width formula the pre-existing connector test
  depended on -- fixed by keeping that original formula exactly
  (`round(band_start + bandwidth)`, summed once, not
  reconstructed from two already-rounded pieces) for the no-total-rows
  case, and only referencing each bar's own actual drawn edge once
  total rows are genuinely in play (new behavior, nothing to preserve
  backward compatibility with there).

  Hand-derived via `python3`, a 4-category start-then-deltas-then-end
  case (`Start` total delta=50, two plain deltas, `End` total delta=0)
  -- every bar's own `band_start`/`bandwidth`/narrow-width-and-inset
  and every connector's own actual-edge position independently re-
  solved, then confirmed against a real `render_svg()` run (twice, once
  per bug above) before trusting the final numbers. Four new tests
  (raster + SVG hand-derived rects and connectors for the total-rows
  case -- including a dedicated check that connectors reference each
  bar's own actual edge, the exact logic bug 2 above was found in --
  plus the `is_total`-length-mismatch raise), all passing alongside
  every pre-existing `Mark.WATERFALL` test, unchanged.
  `examples/waterfall.mojo` updated in place (its own pre-existing
  quarterly-profit-bridge data, now with `Starting`/`Ending` totals
  added -- the classic use case, and its own docstring's earlier "no
  separate total bar... a zero-delta bar wouldn't show anything" caveat
  is exactly what this closes) -- viewed as a rendered PNG (`Starting`
  and `Ending` correctly showing the identical height, confirming a
  net-zero delta sum renders exactly as it should) before considering
  this done.

- **Dynamic legend width** — `_dynamic_legend_width(labels, sc)`
  (plot.mojo): `max(Theme`'s own default 130px `legend_width`,
  `swatch_size + label_gap + widest-label-width + margin_buffer)` --
  the exact same `_max_label_width` measurement technique the dynamic
  *left* margin already uses for y-axis tick labels, applied to legend
  labels instead, `max`'d against the old fixed value so no existing
  plot's own legend column ever gets *narrower* than it already was --
  purely additive. All four legend call sites updated (`Mark.POINT`'s
  own categorical color legend, `Mark.GROUPED_BAR`/`STACKED_BAR`'s own
  series-name legend, `Mark.ARC`'s own category legend); `Mark.POINT`'s
  own `color_categories_domain` (the actual label list) had to move
  earlier in `_render_generic`, computed *before* `plot_x1` is
  finalized rather than deep inside the `Mark.POINT`-specific branch
  where it used to live -- the same "measure the real labels before
  sizing the margin around them" ordering the y-axis's own tick labels
  already require, not a new pattern.

  Confirmed via a real font-metrics probe against this environment's
  own installed fonts, not assumed (`"Southeast Region Sales"` measures
  141.0px at the default 12pt font -- the same "locked in, confirmed by
  probe" convention this file's own wide-y-axis-label test already
  established). Two new tests (`Mark.POINT` and `Mark.GROUPED_BAR`,
  each confirming the legend column shifts to make room for a long
  label) plus the pre-existing short-label legend tests (unchanged,
  still passing) serving as the purely-additive regression check.

  The *bottom*-margin half of this item's own original scope turned out
  not to be well-defined the way the left-margin/legend cases are --
  see "Rotated/diagonal x-axis tick labels," below, for why growing
  `Theme.margin_bottom` itself wouldn't actually solve long x-axis
  category names, and what the real fix looks like instead.

- **Continuous color/size legends** — `Mark.POINT`'s existing
  continuous `color`/`size` encoding (see "Continuous color/size
  encoding," above) drew no legend at all; `_draw_legend`'s own
  swatch-list layout only knows "a list of (label, color) pairs," the
  categorical case, and doesn't generalize to a numeric domain. Two new
  `[T: DrawTarget]`-generic functions instead: `_draw_continuous_color_
  legend` (a vertical gradient bar approximated as
  `_CONTINUOUS_LEGEND_BAR_STEPS` (20) thin solid `fill_rect` strips,
  each the `ColorScale.color_at` color at its own strip's midpoint
  value -- `DrawTarget` deliberately has no gradient-fill primitive, see
  this file's own module docstring, so a real gradient isn't an option
  here; 20 strips reads as smooth at the legend's own small size) with
  `domain_max`/`domain_min` numeric labels top/bottom, and
  `_draw_continuous_size_legend` (three representative circles at the
  data's own min/mid/max, each sized via the same `LinearScale` the
  marks themselves use, with its own numeric label). Both return the y
  position just below what they drew, so multiple legend sections (e.g.
  a bubble chart's color legend *and* size legend) stack vertically in
  one column rather than overlapping.

  `_dynamic_legend_width` (see above) generalized to take a
  `content_width: Int` parameter instead of assuming a fixed swatch
  size, so the same width-growing logic applies whether the legend's
  own left-hand content is a small category swatch, a wider gradient
  bar, or the largest size-legend circle's own diameter.
  `_render_generic`'s `Mark.POINT` setup restructured so
  `color_categories_domain`/`color_mm`/`color_scale`/`size_mm`/
  `size_scale` are all computed early (before `plot_x1` is finalized,
  same ordering "Dynamic legend width" above already established), and
  `show_legend` now also covers plain `has_color`/`has_size` (previously
  only `has_color_categories` reserved legend space) -- purely additive
  in the categorical case (unchanged), new legend space reserved only
  when continuous `color`/`size` encoding is actually present.

  Confirmed via `examples/bubble.mojo` (rewritten to add an SVG
  counterpart alongside its existing raster output, this session's
  standing convention for new/updated features) -- both channels driven
  by the same third variable, rendering a gradient bar labeled with its
  own real min/max plus three size circles labeled 10.0/5.5/1.0,
  visually confirmed correct and legible on the first real render.
  Hand-derived strip colors/positions and circle radii/positions
  (cross-checked in Python against `ColorScale`/`LinearScale`'s own
  already-hand-verified math, not read off the code's own output) in
  three new tests, plus a fourth confirming the legend stays off when
  `Theme.show_legend=False`. Two pre-existing hand-derived-pixel tests
  (`test_render_color_encoding_matches_hand_derived_colors`,
  `test_render_size_encoding_matches_hand_derived_radii`) needed
  `show_legend=False` added to their own `Theme` -- they're about the
  color/size *math*, not legend layout, and the new default-on legend
  now reserves horizontal space that would otherwise shift their
  hand-derived pixel positions; legend layout itself is covered by the
  new tests above instead. All 119 tests passing.

- **`Plot.labels()` precise centering on the inner plot rect** — every
  `_render_*` function (`_render_generic` and the ten mark-specific
  functions it dispatches to) now returns a `_RenderResult` instead of
  a bare `List[_TextRequest]`: the same text-request list as before,
  plus the *actual* inner plot rect it laid the mark out in (`px0`/
  `py0`/`px1`/`py1` -- dynamic left margin, optional legend column, all
  already resolved). `_apply_labels` split into two phases: it still
  reserves outer margin for `Plot.labels()`'s own title/x_title/y_title
  *before* `_render_generic` runs (unchanged), but building their
  `_TextRequest`s (`_label_text_requests`, new) moved to *after* it
  returns, so a title/x_title's own horizontal center (and y_title's
  own vertical center) uses the real inner rect instead of the full
  outer bounds -- each title's *along*-axis position (how far from the
  very top/bottom/left edge) still comes from the original outer
  bounds, unaffected; only the *cross*-axis centering coordinate
  changed. `_CategoricalFrame`/`_HorizontalCategoricalFrame` (the
  shared layout structs `_draw_categorical_axis_frame`/`_draw_
  horizontal_categorical_axis_frame` return) gained the same four
  fields so every categorical-x mark's own `_render_*` function could
  report its rect back without re-deriving it from scale range
  internals.

  Confirmed via `test_render_svg_labels_matches_hand_derived_title_and_
  axis_titles` (tests/test_plot.mojo) -- its own pre-existing hand-
  derived title/x_title/y_title positions all changed (title/x_title's
  `x` from 200 to 229, y_title's `y` from 150 to 137) once the fix
  landed, re-derived and confirmed correct rather than left stale --
  and a new dedicated regression test, `test_render_svg_title_centers_
  on_inner_plot_rect_not_outer_bounds`, using the same long-category-
  name legend setup "Dynamic legend width" above already established
  (`plot_x1` narrowed to 213 by a 167px legend column): the title now
  centers at `(60+213)//2=136`, not the legend-oblivious outer-bounds
  center `(0+400)//2=200` it would have used before this fix.
  `examples/titles.mojo` changed from a plain `Mark.BAR` to `Mark.
  GROUPED_BAR` specifically so its own legend visibly demonstrates the
  fix (a title that stays correctly centered over the legend-narrowed
  data area, not drifting toward the legend column) -- viewed as a
  rendered PNG before considering this done. All 120 tests passing.

- **`Plot.labels()` reaches `render_facets`/`render_facets_svg`/
  `render_layers`/`render_layers_svg`** — the design question this
  entry's own earlier "Explicitly still open" version raised (does a
  facet grid get one shared title, or one per cell? does a layered
  plot's title come from which of its several `Plot`s?) resolved by
  following each function's own existing "where does shared chrome
  come from" precedent rather than inventing a new rule: `render_
  facets`/`render_facets_svg` give each cell its own fully independent
  `Plot` already (own margins, own axes, own mark type) -- a per-cell
  title, from that cell's own `Plot.labels()` call, is the only reading
  consistent with that; `render_layers`/`render_layers_svg` already
  source every other piece of shared chrome (`Theme`, margins, axis
  styling) from `plots[0]` alone -- `Plot.labels()`'s title/x_title/
  y_title follow the identical rule, not a new one.

  `_render_facets_generic`'s own per-cell loop now runs `_apply_labels`/
  `_render_generic`/`_label_text_requests` in sequence for each cell
  (the same three-call shape `render()`/`render_svg()` themselves use,
  just once per cell instead of once for the whole target) rather than
  calling `_render_generic` alone. `_render_layers_generic` converted
  to return a `_RenderResult` too (previously a bare `List[_TextRequest]`,
  the one `_render_*` function this session's earlier "precise
  centering" pass hadn't touched, since it doesn't call `_render_
  generic` internally -- it has its own inline shared-domain layout);
  `render_layers`/`render_layers_svg` call `_apply_labels(plots[0], ...)`
  once before it and `_label_text_requests(plots[0], ...)` once after,
  guarded behind `len(plots) > 0` first -- `_apply_labels` needs a real
  `plots[0]` to read title strings from, and an empty `plots` list is a
  real, already-tested no-op (`test_render_layers_with_empty_list_is_a_
  noop`) that has to stay a no-op.

  Confirmed via three new hand-derived SVG tests (`test_render_facets_
  svg_each_cell_gets_its_own_independent_title` -- one cell titled, the
  other not, confirming the title-driven layout shift stays scoped to
  its own cell; `test_render_layers_svg_title_from_plots0_centers_on_
  shared_inner_rect` -- the shared title's own top-margin reservation
  shifts every layer's geometry together, since they share one inner
  rect; `test_render_layers_with_empty_list_and_a_title_is_still_a_
  noop` -- the empty-list guard specifically) plus the full pre-existing
  facets/layers suite passing unchanged (no title set is still purely
  additive -- `_apply_labels` reserves zero extra margin when every
  title string is empty). `examples/facets.mojo`/`facets_svg.mojo` now
  caption each region's own cell ("North"/"South"/"East"/"West");
  `examples/layers.mojo` captions the whole combined chart from its
  first layer ("Actual vs. Forecast Revenue") -- both viewed as
  rendered images before considering this done. All 123 tests passing.

- **`render_layers` per-point encoding and legends** — scoped, on
  direct instruction, to per-point `color`/`color_categories`/`size`
  encoding within a single `Mark.POINT` layer (exactly what a
  standalone `Mark.POINT` plot already supports), not a per-*series*
  "which layer is which" legend across several flat-colored layers --
  the latter needs a new per-series name field on `Plot` this codebase
  doesn't have yet, a real, separate feature (see "Explicitly still
  open," below); `Mark.BAR`/`GROUPED_BAR`/`STACKED_BAR`/`ARC` layering
  itself stays deferred too (unclear cross-mark domain-sharing design,
  better resolved once real usage informs it than guessed at now).

  A `Mark.POINT` layer's own `color`/`color_categories`/`size` behave
  exactly like the single-plot path (same validation errors, same
  `ColorScale`/palette/`LinearScale` machinery, same legend section
  types/stacking order -- see "Continuous color/size legends," above)
  -- each encoding-using layer's own domain (color scale, size scale,
  category palette) computed independently of every other layer's, the
  same independence `mark_color`/`point_radius`/`line_width` already
  had per layer. `_render_layers_generic` gained the identical
  `legend_reserve` pre-scan pass `_render_generic`'s own single-plot
  legend already uses (computed across every encoding-using layer,
  `max`'d into one shared column width, before `plot_x1` is finalized),
  and a `legend_y` cursor shared across every encoding-using layer's
  own section(s) so multiple layers' legends stack in one column,
  layer order, rather than overlapping. `render_layers()`'s own
  pre-existing "only Mark.POINT/LINE/AREA, no per-point encoding" gap
  now raises the identical error `Plot.encode`'s single-plot path
  already raises when a `LINE`/`AREA` layer tries to use `color`/
  `color_categories`/`size`, rather than silently ignoring it the way
  the pre-this-feature version used to.

  Confirmed via three new tests: a hand-derived SVG test (a single
  `color_categories`-encoded `Mark.POINT` layer -- narrowed `plot_x1`
  from the legend reservation re-solving every point's own pixel
  position, cross-checked in Python against the same `LinearScale`
  slope/intercept formula every hand-derived pixel test in this file
  uses, plus the legend's own two swatch rows), a raises-test for the
  `LINE`+`color_categories` rejection, and `examples/layers.mojo`
  updated to color its own forecast-checkpoint layer by "Ahead"/
  "Behind" status (computed from the actual-vs-forecast data itself,
  not a separate hand-typed column) -- viewed as a rendered image
  (legend correctly reserving space, the title still correctly
  centered over the legend-narrowed area per the "precise centering"
  fix above, the line layer unaffected) before considering this done.
  All 125 tests passing.

- **`test_plot.mojo` split into one file per Mark type** — the single
  2743-line, 125-test file this section's own entries above kept
  growing was, by itself, most of `pixi run test`'s wall-clock cost:
  Mojo compiles it as one translation unit, so touching one mark's own
  test (say, a single `Mark.BULLET` assertion) forced a full recompile
  of all 125 tests, not just that mark's own handful. Split into 21
  files -- one per `Mark` type (`test_point.mojo`, `test_line.mojo`,
  `test_bar.mojo`, `test_area.mojo`, `test_arc.mojo`,
  `test_lollipop.mojo`, `test_waterfall.mojo`, `test_box.mojo`,
  `test_candlestick.mojo`, `test_bullet.mojo`, `test_gantt.mojo`,
  `test_grouped_bar.mojo`, `test_stacked_bar.mojo`,
  `test_histogram.mojo`) plus files for mechanics that cut across marks
  rather than belonging to one (`test_legends.mojo`, `test_margins.mojo`
  -- the dynamic-left-margin tests, `test_facets.mojo`,
  `test_layers.mojo`, `test_labels.mojo`, `test_theme.mojo` -- the
  `Theme.scale` tests, and `test_core.mojo` for generic
  `Plot.encode()`/`render()` validation and the `_unique_categories`/
  `_index_of` utility-function tests) -- plus `tests/_test_helpers.mojo`
  for the two small cross-file helpers (`_count_color`, `_assert_color`,
  and the shared `BG` constant) every split file needs.
  `tests/`/`examples/` still deliberately aren't real Mojo packages (no
  `__init__.mojo` -- see this file's package-declaration mechanics,
  above, and `pixi.toml`'s own comments for why: a package directory
  can't contain a `main()` anywhere under it, and every test/example
  file here has its own `main()`), so a plain `from _test_helpers
  import ...` needs an extra `-I tests` alongside every split file's
  usual `-I .` -- confirmed empirically (not assumed) that Mojo
  resolves single-file, non-package imports this way before committing
  to the design; wired into every `test_*.mojo` line of `pixi.toml`'s
  own `test` task chain, not just added to `dataviz_mojo`'s own build
  config. Purely a file reorganization -- no test body's own assertions
  changed, every one of the original 125 tests still exists, unchanged,
  in its new file. Confirmed via the full `pixi run test` chain: 142
  tests (125 from the split files + the 17 pre-existing `test_scale.
  mojo`/`test_color_scale.mojo`/`test_ordinal_scale.mojo` tests these
  never touched), all passing.

## Removed

- **Table: a named-column data source** — built (a `Table` struct
  resolving named columns down onto the plain `List[Float64]`/
  `List[String]` columns `encode()`/`encode_categorical()` take, plus
  `Plot.encode_from()`/`encode_categorical_from()` as the name -> column
  resolution layer), then deliberately removed: explicit direction that
  this package doesn't need to invent a Table/DataFrame abstraction at
  all -- a 1-D array (`List[Float64]`/`List[String]`) being the one
  data shape every chart type here actually needs is sufficient, and a
  second, parallel way to hand the same data to `encode()` wasn't
  earning its own keep without a concrete caller juggling enough named
  columns to need it. `encode()`/`encode_categorical()` themselves were
  never anything but plain-`List` in, so removing `Table` needed no
  change to what either of those means -- only deleting the table.mojo
  module, its own tests, its own example (`table_source.mojo`), and the
  two `Plot` methods that resolved through it. This file's own earlier
  "Table: a named-column data source" entry documented the design in
  full before this reversal (column storage shape, the `encode_from`/
  `encode_categorical_from` resolution layer, a real `Movable`-vs-
  `ImplicitlyCopyable` bug caught and fixed along the way) -- not
  reproduced here now that the design itself no longer exists to
  explain; this entry exists so a future reader knows the omission was
  deliberate, not an oversight.

## Explicitly still open (deferred until real usage informs them, not forgotten)

- **`Mark.BAR`/`Mark.GROUPED_BAR`/`Mark.STACKED_BAR`/`Mark.ARC` layering**
  — `render_layers` (see Done, above) is scoped to `Mark.POINT`/`LINE`/
  `AREA`; layering bars (plain, grouped, or stacked) or arcs (concentric
  donuts sharing one center) is real, separate work --
  each mark's own domain shape (bands, angular sweep) needs its own
  answer for what "shared" even means, not a small extension of the
  continuous-domain concatenation `render_layers` does today.
- **Per-*series* name/legend within `render_layers`** — a caller
  distinguishing several layers by flat color alone (each layer's own
  `Theme.mark_color`, not per-point encoding within one layer -- see
  "render_layers per-point encoding and legends," Done, above, for
  that already-supported case) still has no "which layer is which"
  legend to label them with -- `Plot` has no per-series name/label
  field yet for one to be built from, a real, separate feature from
  per-point encoding.
- **Rotated/diagonal x-axis tick labels for long category names** —
  unlike the dynamic *left* margin (y-axis labels, drawn to the left of
  their own tick, so a wider label directly needs a wider margin --
  see Done, above, for both that and the now-also-dynamic legend
  column), growing `Theme.margin_bottom` itself wouldn't actually fix
  long x-axis category names: those labels are drawn horizontally,
  single-line, *centered under* their own tick, so a wider label needs
  more *horizontal* room (risking overlap with its neighbors), not more
  vertical space below the axis -- more bottom margin doesn't touch
  that problem at all. The real fix is rotating long x-tick labels
  (diagonal, the common convention other charting libraries reach for
  here) when they'd otherwise overlap -- genuinely new work, not a
  small extension of the dynamic-margin mechanism: `_TextRequest`
  already supports `rotation` (added for `Plot.labels()`'s own y-axis
  title), but deciding *when* labels are wide enough to need it, and
  how the freed-up bottom margin then gets sized for a diagonal label's
  own vertical extent instead of a horizontal one's, is real, separate
  design work.
