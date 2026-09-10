"""The package's concise public API: chart constructors, the `Plot`/`Theme`
core, rendering operations, and commonly used plotting enums.

Specialist vocabulary stays in its named public module: colors in
`dataviz.colors`, colormaps in `dataviz.colormaps`, histogram utilities in
`dataviz.histogram`, scales in `dataviz.scale`/`dataviz.color_scale`, theme
presets in `dataviz.themes`, markers in `dataviz.marker`, and custom-container
traits in `dataviz.array_like`.
"""

from dataviz.theme import Theme
from dataviz.mark import Mark
from dataviz.output_format import OutputFormat
from dataviz.legend_position import LegendPosition
from dataviz.line_style import LineStyle
from dataviz.step_style import StepStyle
from dataviz.x_label_rotation import XAxisLabelRotation
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

# One-call chart functions defined in their mark modules.
from dataviz.arc import pie
from dataviz.bar import bar
from dataviz.barbs import barbs
from dataviz.beeswarm import beeswarm
from dataviz.box import box
from dataviz.bullet import bullet
from dataviz.candlestick import candlestick
from dataviz.contour import contour, contourf
from dataviz.ecdf import ecdf
from dataviz.residplot import residplot
from dataviz.barplot import barplot, countplot
from dataviz.lineplot import lineplot
from dataviz.stats import ErrorBar, Estimator
from dataviz.image import imshow, pcolormesh
from dataviz.kde import kdeplot, rugplot
from dataviz.tricontour import tricontour, tricontourf
from dataviz.triplot import tripcolor, triplot
from dataviz.chord import chord
from dataviz.arc_diagram import arc_diagram
from dataviz.graph import graph
from dataviz.sankey import sankey
from dataviz.effect_scatter import effect_scatter
from dataviz.eventplot import eventplot
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
from dataviz.polar import polar
from dataviz.polar_bar import polarbar
from dataviz.radialbar import radialbar
from dataviz.gauge import gauge
from dataviz.parallel import parallel
from dataviz.radar import radar
from dataviz.population_pyramid import population_pyramid
from dataviz.single_axis import single_axis
from dataviz.stacked_bar import stacked_bar
from dataviz.stack_baseline import StackBaseline
from dataviz.streamgraph import stacked_area, streamgraph
from dataviz.ridgeline import ridgeline
from dataviz.violin import violin
from dataviz.waterfall import waterfall
