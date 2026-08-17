Mojo function [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/plot.mojo)

# `render_facets_svg`

```mojo
fn def render_facets_svg(mut svg: SvgCanvas, plots: List[Plot], cols: Int)
```

`render_facets()`'s exact counterpart for `SvgCanvas` -- same shared `_render_facets_generic` core, `SvgCanvas.draw_text` in place of `canvas_mojo.text.draw_text` for the returned labels, the same relationship `render_svg()` has to `render()` (see that function's own docstring).

**Args:**

- **svg** (`SvgCanvas`)
- **plots** (`List[Plot]`)
- **cols** (`Int`)

**Raises:**

