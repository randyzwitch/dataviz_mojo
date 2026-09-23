---
title: Layers and secondary axes
weight: 40
---

Layers place several plots in one coordinate frame. They share the x-domain;
primary layers also share one y-domain. Drawing order follows list order.

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

Bar layers with identical categories in the same order share a categorical
axis. Each bar layer takes one adjacent slot within its category; optional
point, line, and area layers align to the center of the whole category. Name
and color each bar layer to make the groups readable:

```mojo
from dataviz import Plot, Theme, save_layers
from dataviz.core.colors import CORNFLOWERBLUE, TOMATO

def main() raises:
    var categories: List[String] = ["North", "South", "West"]
    var actual: List[Float64] = [18.0, 24.0, 20.0]
    var plan: List[Float64] = [20.0, 22.0, 21.0]
    var a = (
        Plot().mark_bar().encode_categorical(x=categories, y=actual)
        .series_name("Actual").theme(Theme(mark_color=CORNFLOWERBLUE))
    )
    var b = (
        Plot().mark_bar().encode_categorical(x=categories, y=plan)
        .series_name("Plan").theme(Theme(mark_color=TOMATO))
    )
    save_layers([a^, b^], "bar-layers.svg")
```

Use a secondary axis only when the layers have different units, and label the
right axis. At least one layer must remain primary. Layers must share size, and
categorical, polar, hierarchy, and network marks generally cannot share the
continuous frame. Use facets when plots do not share compatible coordinates.

See [Shared-axis layers](../../cookbook/combo_chart/),
[Dual y-axis](../../cookbook/dual_axis/), and
[layer rendering](../../dataviz/layers/).
