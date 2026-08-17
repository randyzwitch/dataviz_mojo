Mojo function [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/plot.mojo)

# `render`

```mojo
fn def render(mut canvas: Canvas, plot: Plot, ox0: Int = Int(0), oy0: Int = Int(0), ox1: Int = Int(-1), oy1: Int = Int(-1))
```

Render `plot` into `canvas` -- fills its own outer bounds (background, then gridlines, axes, tick labels, and finally the mark itself, in that back-to-front order) rather than compositing into whatever was there before.

`ox0`/`oy0`/`ox1`/`oy1` default to the whole canvas (`ox1`/`oy1`'s
default of -1 means "canvas.width"/"canvas.height" -- a real
negative bound is never meaningful, so it's a safe sentinel, not
an ambiguous one) -- every existing single-plot call keeps
rendering into the entire canvas exactly as before. Passing a
narrower rectangle instead (what `render_facets()` does, one call
per grid cell) makes this one plot's own margins, axes, and
optional legend lay out relative to that sub-rectangle instead of
the whole canvas -- the plot has no idea it's sharing a canvas
with anything else.

A thin wrapper around `_render_generic` (see this module's own
docstring for why rendering is split this way): resolves the
sentinel bounds against `canvas`'s own size, reserves room for any
`Plot.labels()` title/axis titles via `_apply_labels` (see its own
docstring for why that happens *here*, not inside `_render_generic`
itself), hands the shrunk rect off to the shared generic core for
everything else, then builds the title(s)' own `_TextRequest`s via
`_label_text_requests` -- only now, using the *inner* plot rect
`_render_generic` actually returned (`_RenderResult`'s own `px0`..
`py1`), so a title/x_title centers on the real data area rather
than the full outer bounds (see `_apply_labels`'s own docstring for
why this is a two-phase split) -- and finally draws every
`_TextRequest` (the title(s) plus whatever `_render_generic` itself
returned) via `canvas_mojo.text.draw_text` -- the one piece
`_render_generic` itself can't do, since it's generic over any
`DrawTarget` and drawing real text needs `canvas_mojo.text`'s own
native glyph machinery, specific to this raster path (see
`_TextRequest`'s own docstring).

The whole *original* `(ox0, oy0)`-`(cx1, cy1)` rect is filled with
`theme.background` before anything else -- not just the shrunk
inner rect `_render_generic` goes on to fill again itself -- so a
title's own reserved margin strip gets painted too, rather than
showing whatever `canvas` held before this call (which usually
happens to match anyway, but isn't guaranteed to).

**Args:**

- **canvas** (`Canvas`)
- **plot** (`Plot`)
- **ox0** (`Int`)
- **oy0** (`Int`)
- **ox1** (`Int`)
- **oy1** (`Int`)

**Raises:**

