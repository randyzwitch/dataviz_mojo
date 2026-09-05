"""Named colors: the full CSS Color Module Level 3 / X11 "extended color
keywords" list (<https://www.w3.org/TR/css-color-3/#svg-color>) plus
`REBECCAPURPLE` (Level 4), as `Color` constants, so
`Theme(mark_color=CORNFLOWERBLUE)` works instead of
`Theme(mark_color=Color(100, 149, 237))` (#10).

The constants themselves moved to `canvas.named_colors` in canvas_mojo
v0.18.0 -- this file's own docstring had said they could, "if another
consumer wants the list", and one did. This module stays as a
re-export rather than being deleted: `from dataviz.colors import RED`
is the import the cookbook recipes and several `Example:` docstrings
use, and it appears on the docs site, so removing the module would
break documented usage for no gain. `from dataviz import RED` keeps
working through `dataviz/__init__.mojo`'s star-import of this module.

Names and values are unchanged by the move: all 148 constants match
the previous list exactly, name for name and value for value.
"""

from canvas.named_colors import *
