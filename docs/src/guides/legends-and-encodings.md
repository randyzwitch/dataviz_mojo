---
title: Legends and visual encodings
weight: 30
---

An encoding maps a data column to a visual channel. Numeric `x` and `y` control
position. `color`, `color_categories`, `size`, and `labels` add continuous
color, categorical color, point size, and per-point text.

```mojo
from dataviz import Plot, save

def main() raises:
    var plot = (
        Plot()
        .mark_point()
        .encode(
            x=[1.0, 2.0, 3.0, 4.0],
            y=[8.0, 5.0, 9.0, 6.0],
            color_categories=["East", "West", "East", "West"],
        )
        .labels(title="Revenue by Region")
    )
    save(plot, "encoding.svg")
```

Legends are derived from encodings; flat `Theme.mark_color` does not need one.
For layered charts, call `.series_name()` on each layer to create one legend
row per named layer. Keep the number of categories small enough to distinguish,
and use shape as well as color when hue alone is insufficient.

See [Color by category](../../cookbook/color_categorical/),
[Layer legend](../../cookbook/layer_legend/), and
[`Plot.encode`](../../dataviz/plot/Plot/#encode).
