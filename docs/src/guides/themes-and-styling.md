---
title: Themes and styling
weight: 20
---

`Theme` holds presentation choices; data and encodings stay on `Plot`. Calling
`.theme()` attaches a complete theme, so construct the final theme before
attaching it rather than expecting several theme calls to merge.

```mojo
from dataviz import Plot, Theme, save
from dataviz.colors import SEAGREEN

def main() raises:
    var plot = (
        Plot()
        .mark_point()
        .encode(x=[1.0, 2.0, 3.0], y=[2.0, 5.0, 4.0])
        .labels(title="Styled Points")
        .theme(Theme(mark_color=SEAGREEN, point_radius=7.0))
    )
    save(plot, "styled.svg")
```

Theme values cover canvas, axes, typography, marks, legends, annotations, and
output. Presets provide coherent starting points: `dark()`, `minimal()`,
`high_contrast()`, and `print_safe()`. Modify the returned `Theme` before
attaching it when a preset needs an override.

See the [theme recipes](../../cookbook/),
[`Theme`](../../dataviz/theme/Theme/), and
[theme presets](../../dataviz/themes/).
