"""The package's concise public API: chart constructors, the `Plot`/`Theme`
core, rendering operations, and commonly used plotting enums.

Specialist vocabulary stays in its named public module: colors in
`dataviz.core.colors`, colormaps in `dataviz.core.colormaps`, histogram utilities in
`dataviz.binned.histogram`, scales in `dataviz.core.scale`/`dataviz.core.color_scale`, theme
presets in `dataviz.core.themes`, markers in `dataviz.core.marker`, and custom-container
traits in `dataviz.core.array_like`.
"""

from dataviz.core.theme import Theme
from dataviz.core.mark import Mark
from dataviz.core.output_format import OutputFormat
from dataviz.core.axis_position import AxisPosition
from dataviz.spatial.scatter3d import plot3d, scatter3d
from dataviz.spatial.bar3d import bar3d, voxels
from dataviz.spatial.stem3d import fill_between3d, quiver3d, stem3d
from dataviz.spatial.surface3d import surface3d, trisurf3d, wire3d
from dataviz.aggregation.clustermap import (
    clustermap,
    clustermap_pdf,
    clustermap_svg,
)
from dataviz.aggregation.jointplot import (
    jointplot,
    jointplot_pdf,
    jointplot_svg,
)
from dataviz.aggregation.pairplot import (
    pairplot,
    pairplot_pdf,
    pairplot_svg,
)
from dataviz.core.delaunay import Triangulation, delaunay
from dataviz.core.legend_position import LegendPosition
from dataviz.core.line_style import LineStyle
from dataviz.core.step_style import StepStyle
from dataviz.core.x_label_rotation import XAxisLabelRotation
from dataviz.plot import (
    Plot,
    area,
    line,
    render,
    render_facets,
    render_facets_pdf,
    render_facets_svg,
    render_layers,
    render_layers_pdf,
    render_layers_svg,
    render_pdf,
    render_svg,
    save,
    save_facets,
    save_layers,
    scatter,
)

# Unequal-cell composition (#347). Imported directly rather than
# re-exported through plot.mojo, which layout.mojo depends on.
from dataviz.layout import (
    GridCell,
    render_grid,
    render_grid_pdf,
    render_grid_svg,
    render_inset,
    render_inset_svg,
    save_grid,
    uniform_cells,
)

# One-call chart functions defined in their mark modules.
from dataviz.basic.arc import pie
from dataviz.basic.bar import bar
from dataviz.multivariate.barbs import barbs
from dataviz.multivariate.quiver import quiver
from dataviz.multivariate.streamplot import streamplot
from dataviz.distributions.beeswarm import beeswarm
from dataviz.distributions.box import box
from dataviz.distributions.boxen import boxenplot
from dataviz.categorical.bullet import bullet
from dataviz.distributions.candlestick import candlestick
from dataviz.multivariate.contour import contour, contourf
from dataviz.distributions.ecdf import ecdf
from dataviz.aggregation.residplot import residplot
from dataviz.aggregation.barplot import barplot
from dataviz.aggregation.lineplot import lineplot
from dataviz.aggregation.pointplot import pointplot
from dataviz.core.stats import ErrorBar, Estimator
from dataviz.grid.image import imshow, pcolormesh
from dataviz.binned.hist2d import hist2d
from dataviz.binned.hexbin import hexbin
from dataviz.distributions.kde import kdeplot, rugplot
from dataviz.multivariate.tricontour import tricontour, tricontourf
from dataviz.multivariate.triplot import tripcolor, triplot
from dataviz.relationships.chord import chord
from dataviz.relationships.arc_diagram import arc_diagram
from dataviz.relationships.graph import graph
from dataviz.relationships.sankey import sankey
from dataviz.basic.effect_scatter import effect_scatter
from dataviz.distributions.eventplot import eventplot
from dataviz.categorical.bump import bump
from dataviz.categorical.funnel import funnel
from dataviz.categorical.gantt import gantt
from dataviz.categorical.span_chart import span_chart
from dataviz.categorical.grouped_bar import grouped_bar
from dataviz.grid.heatmap import heatmap
from dataviz.grid.calendar_heatmap import calendar_heatmap
from dataviz.grid.corrplot import corrplot
from dataviz.grid.punchcard import punchcard
from dataviz.grid.marimekko import marimekko
from dataviz.hierarchy_marks.dendrogram import dendrogram
from dataviz.hierarchy_marks.sunburst import sunburst
from dataviz.hierarchy_marks.tree import tree
from dataviz.hierarchy_marks.treemap import treemap
from dataviz.binned.histogram import histogram
from dataviz.categorical.lollipop import lollipop
from dataviz.radial.nightingale import nightingale
from dataviz.radial.polar import polar
from dataviz.radial.polar_bar import polarbar
from dataviz.radial.radialbar import radialbar
from dataviz.radial.gauge import gauge
from dataviz.multivariate.parallel import parallel
from dataviz.radial.radar import radar
from dataviz.categorical.population_pyramid import population_pyramid
from dataviz.basic.single_axis import single_axis
from dataviz.categorical.stacked_bar import stacked_bar
from dataviz.core.stack_baseline import StackBaseline
from dataviz.categorical.streamgraph import stacked_area, streamgraph
from dataviz.distributions.ridgeline import ridgeline
from dataviz.distributions.violin import violin
from dataviz.categorical.waterfall import waterfall
