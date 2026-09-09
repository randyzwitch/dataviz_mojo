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

See [Multi-format export](../../cookbook/export_formats/),
[High-DPI export](../../cookbook/high_dpi_export/), and
[save](../../dataviz/plot/save/).
