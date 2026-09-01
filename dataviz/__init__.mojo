"""This package's public surface: everything a caller is meant to
import, re-exported here so `from dataviz import bar, Plot, Theme`
works without anyone needing to know which file inside the package a
given name actually lives in.

That indirection matters most for the one-call convenience functions
(`bar`, `scatter`, `pie`, ...): each one lives in its mark's file,
next to that mark's rendering code (see plot.mojo's module
docstring, its "one-call convenience functions" section, for the rule
and why), so their real module paths -- `dataviz.bar.bar`,
`dataviz.arc.pie` -- are an internal layout detail that would be
noisy and surprising to import directly. Import them from the package,
not from the file.

Every name below is listed explicitly -- a deliberate, considered
addition to this package's public surface -- with one exception:
`colors.mojo`'s ~148 CSS-named `Color` constants (`from dataviz.
colors import *`, the one wildcard import in this file). Those aren't
individually-designed features to enumerate one by one, just a single
fixed, already-standard vocabulary (see that file's docstring) --
listing `RED`, `BLUE`, `CORNFLOWERBLUE`, ... by hand here would be
pure noise a spec already settled, not documentation of a real choice
made in this package.
"""

from dataviz.array_like import Float64Sequence, StringSequence
from dataviz.theme import Theme
from dataviz.mark import Mark
from dataviz.output_format import OutputFormat
from dataviz.scale import LinearScale, MinMax, Ticks
from dataviz.color_scale import ColorScale, default_categorical_palette
from dataviz.colors import *
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import (
    Plot,
    area,
    line,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    save,
    save_facets,
    save_layers,
    scatter,
)

# The remaining one-call convenience functions, each from its mark's
# file -- see this module's docstring for why these are re-exported
# rather than imported from there directly.
from dataviz.arc import pie
from dataviz.bar import bar
from dataviz.beeswarm import beeswarm
from dataviz.box import box
from dataviz.bullet import bullet
from dataviz.candlestick import candlestick
from dataviz.chord import chord
from dataviz.arc_diagram import arc_diagram
from dataviz.graph import graph
from dataviz.sankey import sankey
from dataviz.effect_scatter import effect_scatter
from dataviz.bump import bump
from dataviz.funnel import funnel
from dataviz.gantt import gantt
from dataviz.span_chart import span_chart
from dataviz.grouped_bar import grouped_bar
from dataviz.heatmap import heatmap
from dataviz.calendar_heatmap import calendar_heatmap
from dataviz.corrplot import corrplot
from dataviz.punchcard import punchcard
from dataviz.marimekko import marimekko
from dataviz.sunburst import sunburst
from dataviz.tree import tree
from dataviz.treemap import treemap
from dataviz.histogram import histogram
from dataviz.lollipop import lollipop
from dataviz.nightingale import nightingale
from dataviz.polar import polar, polar_series
from dataviz.polar_bar import polarbar
from dataviz.radialbar import radialbar
from dataviz.gauge import gauge
from dataviz.parallel import parallel
from dataviz.radar import radar
from dataviz.population_pyramid import population_pyramid
from dataviz.single_axis import single_axis
from dataviz.stacked_bar import stacked_bar
from dataviz.streamgraph import streamgraph
from dataviz.ridgeline import ridgeline
from dataviz.violin import violin
from dataviz.waterfall import waterfall
