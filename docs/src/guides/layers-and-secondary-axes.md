---
title: Layers and secondary axes
weight: 40
---

Layers place several plots in one coordinate frame. They share the x-domain;
primary layers also share one y-domain. Drawing order follows list order.

```mojo
from dataviz import Plot, Theme, save_layers
from dataviz.colors import CORNFLOWERBLUE, TOMATO

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var revenue = (
        Plot().mark_line().encode(x=x, y=[80.0, 95.0, 110.0, 125.0])
        .series_name("Revenue").theme(Theme(mark_color=CORNFLOWERBLUE))
    )
    var growth = (
        Plot().mark_line().encode(x=x, y=[4.0, 7.0, 10.0, 8.0])
        .secondary_axis().series_name("Growth %")
        .labels(y_title="Growth (%)").theme(Theme(mark_color=TOMATO))
    )
    save_layers([revenue^, growth^], "layers.svg")
```

Use a secondary axis only when the layers have different units, and label the
right axis. At least one layer must remain primary. Layers must share size, and
categorical, polar, hierarchy, and network marks generally cannot share the
continuous frame. Use facets when plots do not share compatible coordinates.

See [Shared-axis layers](../../cookbook/combo_chart/),
[Dual y-axis](../../cookbook/dual_axis/), and
[layer rendering](../../dataviz/layers/).
