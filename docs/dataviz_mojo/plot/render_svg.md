Mojo function [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/plot.mojo)

# `render_svg`

```mojo
fn def render_svg(mut svg: SvgCanvas, plot: Plot, ox0: Int = Int(0), oy0: Int = Int(0), ox1: Int = Int(-1), oy1: Int = Int(-1))
```

`render()`'s exact counterpart for `SvgCanvas` -- same sentinel-resolution, same `_apply_labels`/`_render_generic` core, same `_TextRequest` lists handed back afterward; the only difference is *how* those get drawn (`SvgCanvas.draw_text`, plain markup emission, no font/glyph machinery involved at all) -- see `render()`'s own docstring for the shared story, and canvas_mojo/ draw_target.mojo's for why text is deferred like this in the first place.

**Args:**

- **svg** (`SvgCanvas`)
- **plot** (`Plot`)
- **ox0** (`Int`)
- **oy0** (`Int`)
- **ox1** (`Int`)
- **oy1** (`Int`)

**Raises:**

