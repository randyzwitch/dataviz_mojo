---
title: Layers and secondary axes
weight: 40
---

Layers place several plots in one coordinate frame. For continuous marks, they
share the x-domain; primary layers also share one y-domain. Drawing order
follows list order.

```mojo
from dataviz import Plot, Theme, save_layers
from dataviz.core.colors import CORNFLOWERBLUE, TOMATO

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

Pies use a separate concentric layout: pass two or more `pie()` plots to
`save_layers()` with the default `inner_radius_fraction=0`. The first plot
is the outer ring, each ring keeps its own proportions, and the legend names
its ring number and category.

```mojo
from dataviz import pie, save_layers

def main() raises:
    var outer_names: List[String] = ["A", "B"]
    var inner_names: List[String] = ["C", "D"]
    var outer_values: List[Float64] = [3.0, 1.0]
    var inner_values: List[Float64] = [2.0, 2.0]
    var outer = pie(outer_names, outer_values, title="Two breakdowns")
    var inner = pie(inner_names, inner_values)
    save_layers([outer^, inner^], "concentric.svg")
```

Use a secondary axis only when the layers have different units, and label the
right axis. At least one layer must remain primary. Layers must share size, and
categorical, other polar, hierarchy, and network marks generally cannot share
the continuous frame. Use facets when plots do not share compatible coordinates.

See [Shared-axis layers](../../cookbook/combo_chart/),
[Dual y-axis](../../cookbook/dual_axis/), and
[layer rendering](../../dataviz/layers/).
