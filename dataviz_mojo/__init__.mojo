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

Every name below is listed explicitly -- a deliberate, considered
addition to this package's own public surface -- with one exception:
`colors.mojo`'s ~148 CSS-named `Color` constants (`from dataviz_mojo.
colors import *`, the one wildcard import in this file). Those aren't
individually-designed features to enumerate one by one, just a single
fixed, already-standard vocabulary (see that file's own docstring) --
listing `RED`, `BLUE`, `CORNFLOWERBLUE`, ... by hand here would be
pure noise a spec already settled, not documentation of a real choice
made in this package.
"""

from dataviz_mojo.theme import Theme
from dataviz_mojo.mark import Mark
from dataviz_mojo.scale import LinearScale, MinMax, Ticks
from dataviz_mojo.color_scale import ColorScale, default_categorical_palette
from dataviz_mojo.colors import *
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
from dataviz_mojo.beeswarm import beeswarm
from dataviz_mojo.box import box
from dataviz_mojo.bullet import bullet
from dataviz_mojo.candlestick import candlestick
from dataviz_mojo.chord import chord
from dataviz_mojo.effect_scatter import effect_scatter
from dataviz_mojo.bump import bump
from dataviz_mojo.funnel import funnel
from dataviz_mojo.gantt import gantt
from dataviz_mojo.grouped_bar import grouped_bar
from dataviz_mojo.heatmap import heatmap
from dataviz_mojo.histogram import histogram
from dataviz_mojo.lollipop import lollipop
from dataviz_mojo.nightingale import nightingale
from dataviz_mojo.population_pyramid import population_pyramid
from dataviz_mojo.single_axis import single_axis
from dataviz_mojo.stacked_bar import stacked_bar
from dataviz_mojo.streamgraph import streamgraph
from dataviz_mojo.ridgeline import ridgeline
from dataviz_mojo.violin import violin
from dataviz_mojo.waterfall import waterfall
