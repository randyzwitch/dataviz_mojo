---
title: Choose a chart
type: docs
weight: 125
---

Start with the question the chart must answer, then choose the simplest form
that makes the comparison visible. Each example link shows runnable source and
rendered output; each API link gives the exact parameters and constraints.

If terms such as mark, encoding, or domain are unfamiliar, see the
[Glossary](../glossary/).

If one convenience function describes the result, use it. Reach for `Plot()`
when you need layers, facets, or additional encodings. Both approaches return
the same `Plot` type.

## Compare categories

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Bar | Comparing one value across categories | Category and value columns | A long category list becomes hard to scan; consider horizontal bars | [Example](../examples/basic/bar/) · [API](../dataviz/basic/bar/bar/) |
| Grouped bar | Comparing several series within each category | Categories, series names, and one value list per series | Too many series make each group crowded | [Example](../examples/categorical/grouped_bar/) · [API](../dataviz/categorical/grouped_bar/grouped_bar/) |
| Lollipop | Showing a light-weight ranking or category comparison | Category and value columns | Thin stems are less effective for precise baseline comparisons than bars | [Example](../examples/categorical/lollipop/) · [API](../dataviz/categorical/lollipop/lollipop/) |
| Bullet | Comparing actual, target, and qualitative ranges | One row per measure with value, target, and ranges | Best for a small dashboard set, not a long categorical distribution | [Example](../examples/categorical/bullet/) · [API](../dataviz/categorical/bullet/bullet/) |
| Population pyramid | Comparing two groups across ordered categories | Categories plus left and right value columns | The two sides must use a common scale to support comparison | [Example](../examples/categorical/population_pyramid/) · [API](../dataviz/categorical/population_pyramid/population_pyramid/) |
| Slope | Comparing two endpoints for each series | Two x positions and paired series values | More than two or three time points usually calls for a line chart | [Example](../examples/categorical/slope/) · [Line API](../dataviz/basic/continuous/line/) |
| Bump | Showing rank changes across ordered periods | Periods, series names, and raw values by series | It shows computed rank, not the magnitude behind the rank | [Example](../examples/categorical/bump/) · [API](../dataviz/categorical/bump/bump/) |

## Show change over time

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Line | Showing continuous change or a connected sequence | Numeric x and y columns | Rows connect in input order; sort time data first | [Example](../examples/basic/line/) · [API](../dataviz/basic/continuous/line/) |
| Step | Showing values that remain constant until the next observation | Numeric x and y columns | Choose the step position to match when a new value takes effect | [Example](../examples/basic/line/) · [Line API](../dataviz/basic/continuous/line/) |
| Area | Emphasizing magnitude over a continuous baseline | Numeric x and y columns | Filled shapes can hide overlapping series | [Example](../examples/basic/area/) · [API](../dataviz/basic/continuous/area/) |
| Stepped area | Showing piecewise-constant magnitude over time | Numeric x and y columns | The same step-position semantics as a step line apply | [Example](../examples/basic/area/) · [Area API](../dataviz/basic/continuous/area/) |
| Stacked area | Showing total and component change together | Ordered categories, series names, and values by series | Middle series have no stable baseline for precise comparison | [Example](../examples/categorical/stacked_area/) · [API](../dataviz/categorical/streamgraph/stacked_area/) |
| Streamgraph | Showing the changing composition of many series | Ordered categories, series names, and values by series | The centered baseline prioritizes overall shape over exact values | [Example](../examples/categorical/streamgraph/) · [API](../dataviz/categorical/streamgraph/streamgraph/) |
| Waterfall | Explaining sequential additions and subtractions to a total | Ordered categories and signed deltas | Mark subtotal or total rows explicitly | [Example](../examples/categorical/waterfall/) · [API](../dataviz/categorical/waterfall/waterfall/) |
| Gantt | Showing scheduled intervals by task | Task names, start values, and end values | Overlapping tasks need ordering chosen before plotting | [Example](../examples/categorical/gantt/) · [API](../dataviz/categorical/gantt/gantt/) |
| Span | Comparing intervals without implying a project schedule | Categories, starts, and ends | It communicates ranges, not a continuous trajectory | [Example](../examples/categorical/span_chart/) · [API](../dataviz/categorical/span_chart/span_chart/) |
| Candlestick | Showing open, high, low, and close values by period | Ordered period plus OHLC columns | It is specialized for interval price movement, not general uncertainty | [Example](../examples/categorical/candlestick/) · [API](../dataviz/distributions/candlestick/candlestick/) |
| Calendar heatmap | Finding daily patterns across weeks and months | Dates and one value per date | Color is less precise than position; label or annotate critical values | [Example](../examples/grid/calendar_heatmap/) · [API](../dataviz/grid/calendar_heatmap/calendar_heatmap/) |

## Show distributions

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Histogram | Seeing the shape of one numeric distribution | Raw numeric observations | The bin rule can change the apparent shape | [Example](../examples/distributions/histogram/) · [API](../dataviz/binned/histogram/histogram/) |
| Shared-bin histograms | Comparing distributions on identical intervals | Several samples and common bin edges | Separate bins make panels look comparable when they are not | [Example](../examples/distributions/histogram/) · [Binning API](../dataviz/binned/histogram/shared_bin_edges/) |
| Automatic-bin histogram | Choosing a data-dependent starting bin count | Raw numeric observations and a bin rule | Treat the automatic choice as a starting point, not a universal optimum | [Example](../examples/distributions/histogram/) · [Bin rules](../dataviz/binned/histogram/BinRule/) |
| Box plot | Comparing median, spread, and outliers across groups | Categories and one raw-value list per category | Multimodal distributions can look deceptively similar | [Example](../examples/distributions/box/) · [API](../dataviz/distributions/box/box/) |
| Violin | Comparing full density shapes across groups | Categories and one raw-value list per category | Density depends on bandwidth and is less stable for small samples | [Example](../examples/distributions/violin/) · [API](../dataviz/distributions/violin/violin/) |
| Beeswarm | Showing every observation while separating overlaps | Categories and one raw-value list per category | Large samples become dense and expensive to lay out | [Example](../examples/distributions/beeswarm/) · [API](../dataviz/distributions/beeswarm/beeswarm/) |
| Ridgeline | Comparing many distribution shapes compactly | Categories and one raw-value list per category | Overlap and independent density scaling can hinder magnitude comparison | [Example](../examples/distributions/ridgeline/) · [API](../dataviz/distributions/ridgeline/ridgeline/) |
| Density curve | Showing a smoothed distribution | Raw numeric observations | Bandwidth controls how much structure is smoothed away | [Example](../examples/distributions/kdeplot/) · [API](../dataviz/distributions/kde/kdeplot/) |
| Rug | Showing exact observation positions beneath another distribution view | Raw numeric observations | A rug alone becomes unreadable with many repeated or dense values | [Example](../examples/distributions/rugplot/) · [API](../dataviz/distributions/kde/rugplot/) |
| ECDF | Comparing cumulative proportions without choosing bins | Raw numeric observations | It emphasizes ranks and thresholds rather than local density | [Example](../examples/distributions/ecdf/) · [API](../dataviz/distributions/ecdf/ecdf/) |
| Event plot | Comparing event positions across labeled rows | Row labels and one position list per row | It shows occurrence, not duration or magnitude | [Example](../examples/distributions/eventplot/) · [API](../dataviz/distributions/eventplot/eventplot/) |

## Show relationships and many variables

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Scatter | Seeing association, clusters, and outliers between two variables | Numeric x and y columns | Overplotting can hide density | [Example](../examples/basic/scatter/) · [API](../dataviz/basic/continuous/scatter/) |
| Effect scatter | Emphasizing points with a halo or visual effect | Numeric x and y columns | Decoration should not substitute for an actual data encoding | [Example](../examples/basic/effect_scatter/) · [API](../dataviz/basic/effect_scatter/effect_scatter/) |
| Single axis | Showing values along one numeric dimension | One numeric position per observation | Coincident values overlap without another distinguishing channel | [Example](../examples/basic/single_axis/) · [API](../dataviz/basic/single_axis/single_axis/) |
| Correlation plot | Scanning pairwise correlations across variables | Variable names and a square correlation matrix | Correlation does not establish causation or expose nonlinear structure | [Example](../examples/grid/corrplot/) · [API](../dataviz/grid/corrplot/corrplot/) |
| Parallel coordinates | Comparing observations across many numeric dimensions | One value list per observation and dimension names | Axis order and scaling strongly affect visible patterns | [Example](../examples/fields/parallel/) · [API](../dataviz/multivariate/parallel/parallel/) |
| Radar | Comparing a few named profiles across common indicators | Indicators, maxima, series names, and values by series | Area and angle make precise cross-axis comparisons difficult | [Example](../examples/radial/radar/) · [API](../dataviz/radial/radar/radar/) |
| Polar line | Showing a relationship naturally expressed as angle and radius | Angle and radius columns | Cartesian alternatives are usually easier to read without a circular domain | [Example](../examples/radial/polar/) · [API](../dataviz/radial/polar/polar/) |
| Multi-series polar | Comparing several angle-radius paths | Angles, series names, and radius values by series | Multiple paths can overlap heavily | [Example](../examples/radial/polar/#several-series) · [API](../dataviz/radial/polar/polar/) |
| Wind barbs | Showing vector direction and magnitude at positions | x and y positions plus u and v vector components | Dense fields need enough canvas space to keep glyphs distinct | [Example](../examples/fields/barbs/) · [API](../dataviz/multivariate/barbs/barbs/) |

## Show composition and progress

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Stacked bar | Comparing category totals and their components | Categories, series names, and one value list per series | Interior segments are difficult to compare across bars | [Example](../examples/categorical/stacked_bar/) · [API](../dataviz/categorical/stacked_bar/stacked_bar/) |
| Pie or donut | Showing a small number of parts of one whole | Categories and non-negative values | Angles are hard to compare; avoid many similar slices | [Example](../examples/basic/pie/) · [API](../dataviz/basic/arc/pie/) |
| Marimekko | Showing two categorical proportions at once | Categories, subcategories, and a subcategory-by-category matrix | Both width and height vary, making exact comparison difficult | [Example](../examples/grid/marimekko/) · [API](../dataviz/grid/marimekko/marimekko/) |
| Funnel | Showing values across ordered process stages | Stage names and non-negative values | Width implies magnitude, not causal conversion between stages | [Example](../examples/categorical/funnel/) · [API](../dataviz/categorical/funnel/funnel/) |
| Gauge | Showing one value against a bounded target range | Value plus minimum and maximum | Space-inefficient for comparing many values | [Example](../examples/radial/gauge/) · [API](../dataviz/radial/gauge/gauge/) |
| Nightingale rose | Comparing magnitudes around a categorical circle | Categories and non-negative values | Radius can exaggerate area unless the intended scaling is clear | [Example](../examples/radial/nightingale/) · [API](../dataviz/radial/nightingale/nightingale/) |
| Polar bar | Comparing bars along an angular axis | Categories and non-negative values | Circular position makes ordinary category comparison harder | [Example](../examples/radial/polarbar/) · [API](../dataviz/radial/polar_bar/polarbar/) |
| Radial bar | Showing category progress around a circle | Categories and non-negative values | A linear bar is more precise when radial layout adds no meaning | [Example](../examples/radial/radialbar/) · [API](../dataviz/radial/radialbar/radialbar/) |

## Show hierarchies

All three hierarchy charts use flattened `ids`, `parent_ids`, and leaf
`values`. Exactly one row is the root.

| Chart | Use it when | Watch for | Links |
| --- | --- | --- | --- |
| Tree | Emphasizing parent-child structure | Deep or broad trees need substantial space | [Example](../examples/hierarchical/tree/) · [API](../dataviz/hierarchy_marks/tree/tree/) |
| Treemap | Comparing leaf size within a hierarchy | Small rectangles leave little room for labels | [Example](../examples/hierarchical/treemap/) · [API](../dataviz/hierarchy_marks/treemap/treemap/) |
| Sunburst | Showing hierarchy depth and part-to-whole size together | Outer arcs are harder to compare and label | [Example](../examples/hierarchical/sunburst/) · [API](../dataviz/hierarchy_marks/sunburst/sunburst/) |

## Show flows and networks

These charts use parallel source, destination, and non-negative value columns.

| Chart | Use it when | Watch for | Links |
| --- | --- | --- | --- |
| Sankey | Tracing quantities through directed stages | The graph must be acyclic; crossing flows quickly add clutter | [Example](../examples/relationships/sankey/) · [API](../dataviz/relationships/sankey/sankey/) |
| Chord | Showing weighted connections among a moderate set of entities | Direction and exact values are difficult to compare in a dense circle | [Example](../examples/relationships/chord/) · [API](../dataviz/relationships/chord/chord/) |
| Arc diagram | Showing connections while preserving a meaningful node order | Long arcs can obscure local structure | [Example](../examples/relationships/arc_diagram/) · [API](../dataviz/relationships/arc_diagram/arc_diagram/) |
| Graph | Showing general relationships among nodes | The circular layout is deterministic but does not discover communities | [Example](../examples/relationships/graph/) · [API](../dataviz/relationships/graph/graph/) |

## Show grids, matrices, and fields

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Heatmap | Comparing values across two categorical dimensions | Long-form x, y, and value columns | Color supports pattern finding better than exact lookup | [Example](../examples/grid/heatmap/) · [API](../dataviz/grid/heatmap/heatmap/) |
| Image | Displaying a regular row-major numeric array | A rectangular `z[row][column]` matrix | Row zero appears at the top; size the plot deliberately when aspect matters | [Example](../examples/grid/imshow/) · [API](../dataviz/grid/image/imshow/) |
| Pseudocolor mesh | Displaying a matrix over unequal cell boundaries | x edges, y edges, and a rectangular matrix | Each edge list has one more entry than its matrix dimension | [Example](../examples/grid/pcolormesh/) · [API](../dataviz/grid/image/pcolormesh/) |
| Contour or filled contour | Showing levels across a regular sampled surface | x coordinates, y coordinates, and a rectangular grid | At least a 2-by-2 grid is required; level choices affect the story | [Line example](../examples/fields/contour/) · [Filled example](../examples/fields/contourf/) · [Line API](../dataviz/multivariate/contour/contour/) · [Filled API](../dataviz/multivariate/contour/contourf/) |
| Scattered contour | Estimating levels from irregularly positioned samples | x, y, values, and triangulation-compatible points | Sparse or poorly distributed points can create misleading triangles | [Line example](../examples/fields/tricontour/) · [Filled example](../examples/fields/tricontourf/) · [Line API](../dataviz/multivariate/tricontour/tricontour/) · [Filled API](../dataviz/multivariate/tricontour/tricontourf/) |
| Triangular mesh | Inspecting or coloring an irregular triangulation | Point x/y coordinates and, for color, one value per point | The Delaunay mesh quality depends on the point distribution | [Mesh example](../examples/fields/triplot/) · [Color example](../examples/fields/tripcolor/) · [Mesh API](../dataviz/multivariate/triplot/triplot/) · [Color API](../dataviz/multivariate/triplot/tripcolor/) |
| Punchcard | Comparing activity across two categorical cycles | Two categorical columns and values | Large category products produce many small cells | [Example](../examples/grid/punchcard/) · [API](../dataviz/grid/punchcard/punchcard/) |

## Show three dimensions

Reach for these last. A projection collapses three dimensions onto two, so two
points that look adjacent may be far apart along the view direction, and every
solid hides whatever stands behind it. When the question is about two
variables, or about reading a value, a 2D chart above answers it exactly; these
answer "what does the whole field look like".

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| 3D scatter | Looking for clusters or a trend that needs all three variables at once | Equal-length x, y, and z columns | Depth is lost to the view; rotate `elev`/`azim` and compare before trusting an apparent cluster | [Example](../examples/three_d/scatter3d/) · [API](../dataviz/spatial/scatter3d/scatter3d/) |
| 3D line | Following one path through space in order | Ordered x, y, and z columns | Segments draw in data order, not depth order, so a later segment covers an earlier one it passes behind | [Example](../examples/three_d/plot3d/) · [API](../dataviz/spatial/scatter3d/plot3d/) |
| Surface or wireframe | Showing the shape of a height field -- ridges, saddles, where it falls away | A rectangular `z[row][col]` grid, optional x and y coordinates | Reads values worse than a contour or heatmap of the same grid; the wireframe keeps the far side visible but turns dense grids into a thicket | [Surface example](../examples/three_d/surface3d/) · [Wireframe example](../examples/three_d/wire3d/) · [Surface API](../dataviz/spatial/surface3d/surface3d/) · [Wireframe API](../dataviz/spatial/surface3d/wire3d/) |
| Triangulated surface | The same, from samples that do not sit on a grid | Scattered x, y, and one z per point | Fills across the convex hull, so a concave sampled region gets bridged; one z per (x, y) means no overhangs | [Example](../examples/three_d/trisurf3d/) · [API](../dataviz/spatial/surface3d/trisurf3d/) |
| 3D bars | Comparing a value over two axes when the shape of the field matters more than any one value | Bar centers x and y with heights z | Every bar hides the ones behind it; a heatmap of the same values hides nothing | [Example](../examples/three_d/bar3d/) · [API](../dataviz/spatial/bar3d/bar3d/) |
| Voxels | Displaying a blocky solid -- an occupancy grid, a segmentation | `filled[layer][row][col]` booleans | Only the surface is visible; structure inside the solid needs slices, not this | [Example](../examples/three_d/voxels/) · [API](../dataviz/spatial/bar3d/voxels/) |
| 3D stems | Reading heights at scattered positions, each tethered to the plane | Equal-length x, y, and z columns | Stems always rise from zero; crossing stems cross visibly whichever was drawn last | [Example](../examples/three_d/stem3d/) · [API](../dataviz/spatial/stem3d/stem3d/) |
| 3D arrows | Sampling a vector field at points | Positions x, y, z and components u, v, w | Heads are sized on the page and never foreshorten, so an arrow pointing at the reader keeps a full head on no shaft | [Example](../examples/three_d/quiver3d/) · [API](../dataviz/spatial/stem3d/quiver3d/) |
| 3D ribbon | Showing the gap between two curves through space | Two curves with the same number of samples | Where the curves cross, the ribbon pinches; there is no correct draw order at a fold | [Example](../examples/three_d/fill_between3d/) · [API](../dataviz/spatial/stem3d/fill_between3d/) |

When several charts could work, build the simplest two with the same data and
compare what becomes easiest to see. The [Examples gallery](../examples/)
provides the fastest side-by-side source and output reference.

[← Data shapes](../data-shapes/) · [Browse Examples →](../examples/)
