---
title: Facets and shared scales
weight: 50
---

Facets arrange independent `Plot` values in a uniform grid. Each cell may use
different data, marks, labels, and themes. Dataviz does not split one dataset
by a column automatically; build the cells explicitly.

```mojo
from dataviz import Plot, save_facets

def main() raises:
    var a = Plot().mark_line().encode(
        x=[1.0, 2.0, 3.0], y=[10.0, 15.0, 12.0]
    ).labels(title="North")
    var b = Plot().mark_line().encode(
        x=[1.0, 2.0, 3.0], y=[8.0, 22.0, 18.0]
    ).labels(title="South")
    save_facets([a^, b^], cols=2, path="facets.svg", shared_y_scale=True)
```

Use `shared_y_scale=True` for value-for-value comparison; independent scales
are better when each cell's shape matters. Shared y-scales support point, line,
and effect-scatter cells. Every plot must have the same size. The first plot's
labels provide the document-level accessible title for SVG output.

See [Facets](../../cookbook/facets/),
[Shared facet scale](../../cookbook/shared_facet_scale/), and
[facet rendering](../../dataviz/facets/).
