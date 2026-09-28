"""Named colors: the full CSS Color Module Level 3 / X11 "extended color
keywords" list (<https://www.w3.org/TR/css-color-3/#svg-color>) plus
`REBECCAPURPLE` (Level 4), as `Color` constants, so
`Theme(mark_color=CORNFLOWERBLUE)` works instead of
`Theme(mark_color=Color(100, 149, 237))`.

The constants themselves live in `canvas.named_colors` (moved there in
canvas_mojo v0.18.0, when another consumer wanted the list). This module
re-exports them so colors have a home inside `dataviz`, like the other
specialist vocabulary (colormaps, palettes, markers): the package root
keeps them out of `from dataviz import ...`, and
`from dataviz.core.colors import RED` is the import the docs, cookbook
recipes and `Example:` docstrings use.

Names and values are unchanged by the move: all 148 constants match
the previous list exactly, name for name and value for value.
"""

from canvas.named_colors import *
