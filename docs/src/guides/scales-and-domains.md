---
title: Scales and domains
weight: 10
---

A scale maps data values to positions or colors. Its **domain** is the data
range; its output range is determined by the chart's plot area. Dataviz
computes position domains from the data and adds padding where appropriate.

Use `.scale_x_domain(min, max)` or `.scale_y_domain(min, max)` when charts must
use a fixed reference range. Use `.scale_x_log()` or `.scale_y_log()` when
ratios matter more than absolute differences.

```mojo
from dataviz import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 10.0, 100.0, 1000.0]
    var y: List[Float64] = [2.0, 4.0, 8.0, 16.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .scale_x_log()
        .scale_y_domain(0.0, 20.0)
        .labels(title="Logarithmic X Scale", x_title="Frequency", y_title="Gain")
    )
    save(plot, "scale.svg")
```

Log-scaled values and annotation positions must be strictly positive. Log y is
not available for area marks because their domain includes zero. Explicit
domains apply to continuous-axis marks and facets; layered charts compute a
shared domain instead of accepting per-layer overrides.

See the [log-x](../../cookbook/log_scale_x/) and
[log-y](../../cookbook/log_scale_y/) recipes, and the
[`Plot` scale methods](../../dataviz/plot/Plot/).
