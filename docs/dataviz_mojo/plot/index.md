Mojo module [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/plot.mojo)

# `plot`

Plot -- the fluent builder for this package's first vertical slice: basic X-Y plots (scatter via Mark.POINT, line via Mark.LINE). Data is plain columnar `List[Float64]`/`List[String]`, passed to `encode()`/ `encode_categorical()` directly -- a 1-D array is all any chart type here needs; a named-column `Table` abstraction was built and then removed (see the wiki's Changelog) once it turned out to add a second way to do the same thing without a concrete need for named-column lookup driving it.

Builder methods consume and return `Self` (`var self` -> `return
self^`) so calls chain: `Plot().mark_point().encode(x=xs,
y=ys).theme(t)` -- matches `canvas`'s own Path/Canvas builder feel in
spirit, chained rather than one statement per call since that's the
composition style settled on for this package specifically.

`render(canvas, plot)`/`render_svg(svg, plot)` are the two entry
points that turn a Plot into pixels or into SVG markup -- both a
single batch pass, no retained scene graph and no reactive signals
(see dataviz-api-design for why: `canvas` itself has neither, so
there's nothing for either to attach to yet). By default each owns
the whole target it's given (fills the background, computes margins
from `Theme`, plus any extra margin `Plot.labels()`'s own chart/axis
titles need -- see `_apply_labels`'s own docstring) rather than
compositing into an existing drawing; their optional `ox0`/`oy0`/
`ox1`/`oy1` bounds narrow that to a sub-rectangle instead -- the
mechanism `render_facets()` (small multiples: a grid of independently
laid-out plots on one canvas) composes on top of, without `render()`
itself knowing facets exist.

Both entry points share one generic rendering core (`_render_generic`,
`_render_bar`, `_render_arc` -- each `[T: DrawTarget]`, see canvas/
draw_target.mojo's own docstring for what that trait is and why it
exists) for everything except *text*: `DrawTarget` deliberately has no
`draw_text` method (drawing real text needs `canvas_mojo.text`'s own
native FreeType/fontconfig glyph machinery for the raster path, or
SVG-specific markup for the vector one, and forcing either dependency
onto the other would defeat the point), so text is
collected as a `List[_TextRequest]` while the generic pass runs, then
`render()`/`render_svg()` each draw that list their own way once it
returns -- see `_TextRequest`'s own docstring.

Every raster draw call the generic core makes through `Canvas` is the
anti-aliased variant -- `fill_circle_aa` for points, `stroke_path_aa`
for lines, `draw_line_aa` for gridlines/axis lines/tick marks --
rather than reasoning per call site about whether AA is "worth it."
For the axis-aligned lines specifically this makes no visual
difference (a perfectly horizontal or vertical, integer-positioned
line has no diagonal stepping for AA to smooth away in the first place
-- confirmed directly against draw_line_aa's own coverage math, not
assumed), but there's no real cost to it either given how few short
lines these are, and one consistent default is simpler to reason about
than an exception that has to be re-justified every time someone reads
this file. `SvgCanvas` has no equivalent AA choice to make at all --
an SVG renderer handles that itself, at whatever resolution it's
displayed at (see the wiki's Changelog, its own entry for the concrete
problem that motivated adding it).

## Structs

- [`Plot`](Plot.md)

## Functions

- [`render`](render.md)
- [`render_svg`](render_svg.md)
- [`render_facets`](render_facets.md)
- [`render_facets_svg`](render_facets_svg.md)
- [`render_layers`](render_layers.md)
- [`render_layers_svg`](render_layers_svg.md)

