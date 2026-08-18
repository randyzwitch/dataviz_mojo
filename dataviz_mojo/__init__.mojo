"""This package's own public surface: everything a caller is meant to
import, re-exported here so `from dataviz_mojo import bar, Plot, Theme`
works without anyone needing to know which file inside the package a
given name actually lives in.

That indirection matters most for the one-call convenience functions
(`bar`, `scatter`, `pie`, ...): each one lives in its own mark's file,
next to that mark's own rendering code (see plot.mojo's own module
docstring, its "one-call convenience functions" section, for the rule
and why), so their real module paths -- `dataviz_mojo.bar.bar`,
`dataviz_mojo.arc.pie` -- are an internal layout detail that would be
noisy and surprising to import directly. Import them from the package,
not from the file.
"""

from dataviz_mojo.theme import Theme
from dataviz_mojo.mark import Mark
from dataviz_mojo.scale import LinearScale, MinMax, Ticks
from dataviz_mojo.color_scale import ColorScale, default_categorical_palette
from dataviz_mojo.ordinal_scale import OrdinalScale
from dataviz_mojo.plot import (
    Plot,
    area,
    line,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    scatter,
)

# The remaining one-call convenience functions, each from its own mark's
# file -- see this module's own docstring for why these are re-exported
# rather than imported from there directly.
from dataviz_mojo.arc import pie
from dataviz_mojo.bar import bar
from dataviz_mojo.box import box
from dataviz_mojo.bullet import bullet
from dataviz_mojo.candlestick import candlestick
from dataviz_mojo.gantt import gantt
from dataviz_mojo.grouped_bar import grouped_bar
from dataviz_mojo.histogram import histogram
from dataviz_mojo.lollipop import lollipop
from dataviz_mojo.stacked_bar import stacked_bar
from dataviz_mojo.waterfall import waterfall
