---
title: Themes and styling
weight: 20
---

`Theme` holds presentation choices; data and encodings stay on `Plot`. Calling
`.theme()` attaches a complete theme, so construct the final theme before
attaching it rather than expecting several theme calls to merge.

```mojo
from dataviz import Plot, Theme, save
from dataviz.core.colors import SEAGREEN

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

Categorical charts use the eight-color Okabe-Ito palette by default. Named
alternatives live in `dataviz.core.palettes`:

```mojo
from dataviz import Theme
from dataviz.core.palettes import tol_bright

var theme = Theme(categorical_palette=tol_bright())
```

`tableau_10()` and `tol_muted()` offer more categories, `tol_light()` supplies pale fills behind
dark labels, and `tab10_legacy()` reproduces the previous default. A palette
cycles when categories exceed its length, so use labels or another visual cue
for larger sets.

Theme values cover canvas, axes, typography, marks, legends, annotations, and
output. Presets provide coherent starting points: `dark()`, `minimal()`,
`high_contrast()`, and `print_safe()`. Modify the returned `Theme` before
attaching it when a preset needs an override.

See the [theme recipes](../../cookbook/),
[`Theme`](../../dataviz/core/theme/Theme/), and
[theme presets](../../dataviz/core/themes/).
