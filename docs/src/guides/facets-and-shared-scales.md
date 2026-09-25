---
title: Facets and shared scales
weight: 50
---

Facets arrange independent `Plot` values in a uniform grid. Each cell may use
different data, marks, labels, and themes. Use `scatter_facets()` to make
grouped scatter panels directly from named DataFrame columns, or build cells
explicitly for other marks.

```mojo
from dataviz import Plot, save_facets

def main() raises:
    var a = Plot().mark_line().encode(
        x=[1.0, 2.0, 3.0], y=[10.0, 15.0, 12.0]
    ).labels(title="North")
    var b = Plot().mark_line().encode(
        x=[1.0, 2.0, 3.0], y=[8.0, 22.0, 18.0]
    ).labels(title="South")
    save_facets(a, b, cols=2, path="facets.svg", shared_y_scale=True)
```

For a DataFrame, `scatter_facets(df, x="spend", y="revenue",
facet="region", color="product")` returns plots ready for `save_facets`.
`facet_order` fixes panel order and `color_order` fixes group colors even when
a group is absent from one panel. Both orders must name every observed level.
See [Grouped DataFrame facets](../../cookbook/dataframe_grouped_facets/) for a
complete example.

Use `shared_y_scale=True` for value-for-value comparison; independent scales
are better when each cell's shape matters. Shared y-scales support point, line,
and effect-scatter cells. Every plot must have the same size. The first plot's
labels provide the document-level accessible title for SVG output.

See [Facets](../../cookbook/facets/),
[Shared facet scale](../../cookbook/shared_facet_scale/), and
[facet rendering](../../dataviz/facets/).
