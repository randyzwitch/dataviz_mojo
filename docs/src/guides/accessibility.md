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
`print_safe()` when appropriate. The default categorical palette uses Okabe-Ito
colors, but color alone is still insufficient. For categorical series, combine
shape, position, labels, or line patterns with color. See the [named palettes](../../dataviz/core/palettes/).

Filled shapes have no marker or dash to fall back on, so
`Theme(fill_pattern_by_category=True)` draws a pattern over each category's
fill: pie and donut slices, stacked and grouped bars, funnel steps, streamgraph
bands, treemap and sunburst branches, marimekko cells, nightingale and polar
bar wedges, and population pyramid sides. Each category's `HatchStyle` is dealt
by the same index as its color, legend swatches included, and the first
category stays solid. The patterns are drawn as ordinary lines and dots, so
PNG, SVG and PDF output match.

Colors and patterns are dealt by position, so a category's look changes when
the list does: after `sort_categories()`, or in a facet missing one series.
`fill_colors()` and `fill_patterns()` pin them by name instead, and the legend
follows. A pinned pattern is drawn even with `fill_pattern_by_category` off,
which is how to mark one slice and leave the rest solid. Names a chart does
not have are ignored, so one map can serve every panel of a figure.

See [SVG accessibility](../../cookbook/svg_accessibility/),
[High-contrast theme](../../cookbook/high_contrast_theme/), and
[accessible SVG helpers](../../dataviz/rendering/).
