Mojo function [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/plot.mojo)

# `render_layers`

```mojo
fn def render_layers(mut canvas: Canvas, plots: List[Plot], ox0: Int = Int(0), oy0: Int = Int(0), ox1: Int = Int(-1), oy1: Int = Int(-1))
```

Render every `Plot` in `plots` onto *one shared* coordinate system on `canvas` -- one combined x/y domain (computed across every layered plot's own data together, not each plot's own independent domain the way `render_facets()`'s cells each get), one shared set of axes/gridlines/ticks, each plot's own mark drawn on top of the last in the order given -- a line overlaid on a scatter, three comparison lines sharing one y-axis, and so on.

Restricted to `Mark.POINT`/`LINE`/`AREA` for this first version --
`Mark.BAR`'s categorical x-axis and `Mark.ARC`'s lack of one don't
share a domain shape with continuous marks or each other; layering
those in is real, separate, deferred work (see the wiki's Backlog).
Raises if any layered plot uses a different mark.

A layer whose own mark is `Mark.POINT` can use `color`/`color_
categories`/`size` encoding exactly like a standalone `Mark.POINT`
plot (see `Plot.encode`'s own docstring) -- each such layer's own
domain (color scale, size scale, category palette) is independent
of every other layer's, the same "each layer's own `Theme` only
governs its own mark's appearance" independence `mark_color`/
`point_radius`/`line_width` already have. Raises the identical
"only Mark.POINT" error `Plot.encode`'s own single-plot path raises
if a `LINE`/`AREA` layer tries to use one of these instead. A
caller wanting several distinctly colored *series* instead (rather
than per-point encoding within one series) still sets each layer's
own flat `Theme.mark_color` (the same per-layer-styling `examples/
facets.mojo` already uses, just overlaid here instead of laid out
in a grid) -- `render_layers` still has no per-*series* name/label
concept for a "which layer is which" legend built from several
flat-colored layers (see the wiki's Backlog, its own "Explicitly
still open" section); that's a separate feature from per-point
encoding within a single layer, which this one now supports.

Shared chrome -- background, gridlines, axis colors, margins, font
size, tick spacing -- comes from `plots[0]`'s own `Theme`; every
other layered plot's own `Theme` only governs its own mark's
appearance (`mark_color`, `point_radius`, `line_width`, each still
scaled by that plot's own `Theme.scale` -- see `_Scaled`'s own
docstring). Each encoding-using `Mark.POINT` layer draws its own
legend section(s) (gated by that layer's own `Theme.show_legend`,
not `plots[0]`'s), stacked in one shared column in layer order --
the same categorical/continuous-color/size section types and
stacking order `_render_generic`'s own single-plot `Mark.POINT`
legend already uses (see its own docstring), just once per
encoding-using layer instead of once per plot. The legend column's
own horizontal position is shared (every section starts at the
identical x, from the combined `plot_x1`), but each section's own
row height/font size/colors come from that specific layer's own
`Theme` -- so differently-scaled or differently-styled layers each
draw their own section correctly, not forced through `plots[0]`'s
styling.

`Plot.labels()`'s title/x_title/y_title -- like every other piece of
shared chrome -- come from `plots[0]`'s own labels, not each layer's
own (a layered plot has one combined coordinate system, so one
shared title is the only reading that makes sense here, unlike
`render_facets()`'s own per-cell titles -- see that function's own
docstring). The same `_apply_labels`/`_label_text_requests`
two-phase split `render()`/`render_svg()` use.

`ox0`/`oy0`/`ox1`/`oy1` are the exact same sentinel-bounds
convention `render()` itself uses (see that function's own
docstring) -- default to the whole canvas.

**Args:**

- **canvas** (`Canvas`)
- **plots** (`List[Plot]`)
- **ox0** (`Int`)
- **oy0** (`Int`)
- **ox1** (`Int`)
- **oy1** (`Int`)

**Raises:**

