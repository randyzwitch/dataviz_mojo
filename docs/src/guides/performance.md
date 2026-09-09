---
title: Performance and large datasets
weight: 90
---

Rendering cost depends on the number and complexity of drawn primitives, the
backend, canvas size, and raster supersampling. Measure the chart and workload
you actually plan to ship.

```mojo
from dataviz import Plot, Theme, save

def main() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(10_000):
        x.append(Float64(i))
        y.append(Float64((i * 17) % 101))
    var plot = (
        Plot().mark_point().encode(x=x, y=y)
        .theme(Theme(raster_supersample=1))
        .labels(title="Ten Thousand Points")
    )
    save(plot, "large.png")
```

Start with the default backend and settings, then profile. Avoid labels for
every observation in dense charts. Reduce output dimensions or raster
supersampling when antialiasing is not worth the cost. Aggregation or sampling
can improve both performance and readability, but should preserve the pattern
the chart is meant to show.

Run `pixi run bench` for the repository benchmark suite. See the
[benchmark methodology](https://github.com/randyzwitch/dataviz_mojo/blob/main/benchmarks/METHODOLOGY.md)
and [Data shapes](../../data-shapes/).
