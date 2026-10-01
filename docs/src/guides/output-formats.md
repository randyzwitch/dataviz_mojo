---
title: Raster and SVG output
weight: 70
---

`save()` chooses SVG, PNG, or BMP from the filename extension. SVG stores
shapes and text as vectors; PNG and BMP store a fixed pixel grid.

```mojo
from dataviz import scatter, save

def main() raises:
    var plot = scatter(
        [1.0, 2.0, 3.0], [2.0, 5.0, 4.0], title="Three Observations"
    )
    save(plot, "chart.svg")
    save(plot, "chart.png")
```

Choose SVG for responsive web graphics and sharp print scaling. Choose PNG for
broad image compatibility or pixel-based workflows. BMP is uncompressed and
usually useful only for systems that require it. Raster supersampling improves
curved edges but increases render work and memory. For a higher-density export,
increase both the pixel dimensions and `Theme.scale` by the same factor.

## Recording a chart

`record()` draws a chart once into a canvas_mojo `DisplayList`, which owns
the finished drawing and can be replayed into a `Canvas`, `SvgCanvas` or
`PdfCanvas` as often as needed. Use it when the same figure is drawn many
times, such as a chart in a window that repaints, and use `render()`,
`render_svg()` or `save()` when you draw it once.

```mojo
from canvas import Canvas, FontCache, SvgCanvas
from dataviz import OutputFormat, record, scatter

def main() raises:
    var plot = scatter(
        [1.0, 2.0, 3.0], [2.0, 5.0, 4.0], title="Three Observations"
    )
    var recording = record(plot)
    var cache = FontCache()
    var theme = plot.chart_settings().theme
    var canvas = Canvas(
        plot.canvas_width(), plot.canvas_height(), theme.background
    )
    canvas.begin_supersampled(3, theme.background)
    recording.replay(canvas, cache=cache)
    canvas.end_supersampled()

    var svg = SvgCanvas(plot.canvas_width(), plot.canvas_height())
    record(plot, OutputFormat.SVG).replay(svg, cache=cache)
```

Replayed this way, the recording draws what `render()` and `render_svg()`
draw. `render()` supersamples, so replay into a canvas the same way.
Supersampled replay currently takes longer than a direct `render()`
([canvas_mojo#506](https://github.com/randyzwitch/canvas_mojo/issues/506)).
Pass the output format to `record()` because a few marks draw differently
for vector output.

A recording is one layout at the chart's size. Replaying it under a scale
stretches that layout; it does not pick new ticks or move the legend. To
draw at another size, call `size()` on the chart and record it again. A
chart erased with `erased()` cannot be recorded; erase it with
`erased_with[display_list=True]()` instead.

See [Multi-format export](../../cookbook/export_formats/),
[High-DPI export](../../cookbook/high_dpi_export/), and
[save](../../dataviz/rendering/save/), and
[record](../../dataviz/rendering/record/).
