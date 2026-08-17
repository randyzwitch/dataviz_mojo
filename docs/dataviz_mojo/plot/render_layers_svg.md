Mojo function [🡭](https://github.com/randyzwitch/dataviz_mojo/blob/main/dataviz_mojo/plot.mojo)

# `render_layers_svg`

```mojo
fn def render_layers_svg(mut svg: SvgCanvas, plots: List[Plot], ox0: Int = Int(0), oy0: Int = Int(0), ox1: Int = Int(-1), oy1: Int = Int(-1))
```

`render_layers()`'s exact counterpart for `SvgCanvas` -- same shared `_render_layers_generic` core, `SvgCanvas.draw_text` in place of `canvas_mojo.text.draw_text` for the returned labels, the same relationship `render_svg()` has to `render()`.

**Args:**

- **svg** (`SvgCanvas`)
- **plots** (`List[Plot]`)
- **ox0** (`Int`)
- **oy0** (`Int`)
- **ox1** (`Int`)
- **oy1** (`Int`)

**Raises:**

