---
title: Annotations
weight: 60
---

Annotations add explanation without changing the encoded data. Use a line for
a threshold, an area or band for a range, a point or arrow for an observation,
and a best-fit annotation for a simple linear trend.

```mojo
from dataviz import Plot, save

def main() raises:
    var plot = (
        Plot()
        .mark_point()
        .encode(x=[1.0, 2.0, 3.0, 4.0], y=[3.0, 5.0, 4.0, 8.0])
        .annotate_line(6.0, label="Target")
        .annotate_point(4.0, 8.0, label="Peak")
        .labels(title="Results Against Target")
    )
    save(plot, "annotations.svg")
```

Annotation coordinates use data units and the mark's scale. Out-of-domain
fixed annotations are skipped. Point, arrow, and variable bands require two
continuous axes; horizontal reference lines work with more mark types.
Annotations in facets and layers use the scale of their own cell or layer.

See the [annotation recipes](../../cookbook/) and
[`Plot` annotation methods](../../dataviz/plot/Plot/).
