Mojo function [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/plot.mojo)

# `render_facets`

```mojo
fn def render_facets(mut canvas: Canvas, plots: List[Plot], cols: Int)
```

Render each of `plots` into its own evenly sized grid cell on `canvas` -- see `_render_facets_generic`'s own docstring for the actual cell-layout contract this and `render_facets_svg` share. A thin wrapper exactly like `render()`'s own: resolve `canvas`'s own size, hand off to the shared generic core, draw the `_TextRequest`s it returns via `canvas_mojo.text.draw_text`.

**Args:**

- **canvas** (`Canvas`)
- **plots** (`List[Plot]`)
- **cols** (`Int`)

**Raises:**

