"""The package's public surface. Everything a caller imports is
re-exported here so `from dataviz import bar, Plot, Theme` works
without knowing which file a name lives in.

The one-call convenience functions (`bar`, `scatter`, `pie`, ...) each
live in their mark's file next to its rendering code (see plot.mojo's
module docstring), so their real module paths (`dataviz.bar.bar`,
`dataviz.arc.pie`) are an internal layout detail. Import them from the
package.

Every name is listed explicitly except `colors.mojo`'s ~148 CSS-named
`Color` constants, which come in through the one wildcard import: they
are a fixed standard vocabulary, not individually chosen additions.
"""

from dataviz.array_like import Float64Sequence, StringSequence
from dataviz.theme import Theme
from dataviz.mark import Mark
from dataviz.output_format import OutputFormat
from dataviz.x_label_rotation import XAxisLabelRotation
from dataviz.scale import LinearScale, MinMax, Ticks
from dataviz.color_scale import ColorScale, default_categorical_palette
from dataviz.marker import PointShape, default_marker_shapes
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

# The remaining one-call convenience functions, each from its mark's file.
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
