---
title: Accessibility
weight: 80
---

Accessible charts combine a clear visible title, a text description, readable
contrast, and encodings that do not rely on color alone. SVG can carry this
information as document structure for assistive technology.

```mojo
from dataviz import Plot, save

def main() raises:
    var plot = (
        Plot()
        .mark_line()
        .encode(x=[1.0, 2.0, 3.0], y=[4.0, 7.0, 6.0])
        .labels(
            title="Weekly Orders",
            x_title="Week",
            y_title="Orders",
            description="Orders rise from four to seven, then fall to six.",
        )
    )
    save(plot, "orders.svg")
```

For SVG, `save()` turns the plot title and description into accessible document
markup. Descriptions should communicate the takeaway, not enumerate every pixel.
Check contrast in the final destination and use `high_contrast()` or
`print_safe()` when appropriate. For categorical series, combine shape,
position, labels, or line patterns with color.

See [SVG accessibility](../../cookbook/svg_accessibility/),
[High-contrast theme](../../cookbook/high_contrast_theme/), and
[accessible SVG helpers](../../dataviz/plot/).
