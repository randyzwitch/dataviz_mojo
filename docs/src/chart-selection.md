---
title: Choose a chart
type: docs
weight: 125
---

Start with the question the chart must answer, then choose the simplest form
that makes the comparison visible. Each example link shows runnable source and
rendered output; each API link gives the exact parameters and constraints.

If one convenience function describes the result, use it. Reach for `Plot()`
when you need layers, facets, or additional encodings. Both approaches return
the same `Plot` type.

## Compare categories

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Bar | Comparing one value across categories | Category and value columns | A long category list becomes hard to scan; consider horizontal bars | [Example](../examples/bar/) · [API](../dataviz/bar/bar/) |
| Grouped bar | Comparing several series within each category | Categories, series names, and one value list per series | Too many series make each group crowded | [Example](../examples/grouped_bar/) · [API](../dataviz/grouped_bar/grouped_bar/) |
| Lollipop | Showing a light-weight ranking or category comparison | Category and value columns | Thin stems are less effective for precise baseline comparisons than bars | [Example](../examples/lollipop/) · [API](../dataviz/lollipop/lollipop/) |
| Bullet | Comparing actual, target, and qualitative ranges | One row per measure with value, target, and ranges | Best for a small dashboard set, not a long categorical distribution | [Example](../examples/bullet/) · [API](../dataviz/bullet/bullet/) |
| Population pyramid | Comparing two groups across ordered categories | Categories plus left and right value columns | The two sides must use a common scale to support comparison | [Example](../examples/population_pyramid/) · [API](../dataviz/population_pyramid/population_pyramid/) |
| Slope | Comparing two endpoints for each series | Two x positions and paired series values | More than two or three time points usually calls for a line chart | [Example](../examples/slope/) · [Line API](../dataviz/continuous/line/) |
| Bump | Showing rank changes across ordered periods | Periods, series names, and raw values by series | It shows computed rank, not the magnitude behind the rank | [Example](../examples/bump/) · [API](../dataviz/bump/bump/) |

## Show change over time

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Line | Showing continuous change or a connected sequence | Numeric x and y columns | Rows connect in input order; sort time data first | [Example](../examples/line/) · [API](../dataviz/continuous/line/) |
| Step | Showing values that remain constant until the next observation | Numeric x and y columns | Choose the step position to match when a new value takes effect | [Example](../examples/step/) · [Line API](../dataviz/continuous/line/) |
| Area | Emphasizing magnitude over a continuous baseline | Numeric x and y columns | Filled shapes can hide overlapping series | [Example](../examples/area/) · [API](../dataviz/continuous/area/) |
| Stepped area | Showing piecewise-constant magnitude over time | Numeric x and y columns | The same step-position semantics as a step line apply | [Example](../examples/step_area/) · [Area API](../dataviz/continuous/area/) |
| Stacked area | Showing total and component change together | Ordered categories, series names, and values by series | Middle series have no stable baseline for precise comparison | [Example](../examples/stacked_area/) · [API](../dataviz/streamgraph/stacked_area/) |
| Streamgraph | Showing the changing composition of many series | Ordered categories, series names, and values by series | The centered baseline prioritizes overall shape over exact values | [Example](../examples/streamgraph/) · [API](../dataviz/streamgraph/streamgraph/) |
| Waterfall | Explaining sequential additions and subtractions to a total | Ordered categories and signed deltas | Mark subtotal or total rows explicitly | [Example](../examples/waterfall/) · [API](../dataviz/waterfall/waterfall/) |
| Gantt | Showing scheduled intervals by task | Task names, start values, and end values | Overlapping tasks need ordering chosen before plotting | [Example](../examples/gantt/) · [API](../dataviz/gantt/gantt/) |
| Span | Comparing intervals without implying a project schedule | Categories, starts, and ends | It communicates ranges, not a continuous trajectory | [Example](../examples/span_chart/) · [API](../dataviz/span_chart/span_chart/) |
| Candlestick | Showing open, high, low, and close values by period | Ordered period plus OHLC columns | It is specialized for interval price movement, not general uncertainty | [Example](../examples/candlestick/) · [API](../dataviz/candlestick/candlestick/) |
| Calendar heatmap | Finding daily patterns across weeks and months | Dates and one value per date | Color is less precise than position; label or annotate critical values | [Example](../examples/calendar_heatmap/) · [API](../dataviz/calendar_heatmap/calendar_heatmap/) |

## Show distributions

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Histogram | Seeing the shape of one numeric distribution | Raw numeric observations | The bin rule can change the apparent shape | [Example](../examples/histogram/) · [API](../dataviz/histogram/histogram/) |
| Shared-bin histograms | Comparing distributions on identical intervals | Several samples and common bin edges | Separate bins make panels look comparable when they are not | [Example](../examples/histogram_shared/) · [Binning API](../dataviz/histogram/shared_bin_edges/) |
| Automatic-bin histogram | Choosing a data-dependent starting bin count | Raw numeric observations and a bin rule | Treat the automatic choice as a starting point, not a universal optimum | [Example](../examples/histogram_auto/) · [Bin rules](../dataviz/histogram/BinRule/) |
| Box plot | Comparing median, spread, and outliers across groups | Categories and one raw-value list per category | Multimodal distributions can look deceptively similar | [Example](../examples/box/) · [API](../dataviz/box/box/) |
| Violin | Comparing full density shapes across groups | Categories and one raw-value list per category | Density depends on bandwidth and is less stable for small samples | [Example](../examples/violin/) · [API](../dataviz/violin/violin/) |
| Beeswarm | Showing every observation while separating overlaps | Categories and one raw-value list per category | Large samples become dense and expensive to lay out | [Example](../examples/beeswarm/) · [API](../dataviz/beeswarm/beeswarm/) |
| Ridgeline | Comparing many distribution shapes compactly | Categories and one raw-value list per category | Overlap and independent density scaling can hinder magnitude comparison | [Example](../examples/ridgeline/) · [API](../dataviz/ridgeline/ridgeline/) |
| Density curve | Showing a smoothed distribution | Raw numeric observations | Bandwidth controls how much structure is smoothed away | [Example](../examples/kdeplot/) · [API](../dataviz/kde/kdeplot/) |
| Rug | Showing exact observation positions beneath another distribution view | Raw numeric observations | A rug alone becomes unreadable with many repeated or dense values | [Example](../examples/rugplot/) · [API](../dataviz/kde/rugplot/) |
| ECDF | Comparing cumulative proportions without choosing bins | Raw numeric observations | It emphasizes ranks and thresholds rather than local density | [Example](../examples/ecdf/) · [API](../dataviz/ecdf/ecdf/) |
| Event plot | Comparing event positions across labeled rows | Row labels and one position list per row | It shows occurrence, not duration or magnitude | [Example](../examples/eventplot/) · [API](../dataviz/eventplot/eventplot/) |

## Show relationships and many variables

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Scatter | Seeing association, clusters, and outliers between two variables | Numeric x and y columns | Overplotting can hide density | [Example](../examples/scatter/) · [API](../dataviz/continuous/scatter/) |
| Effect scatter | Emphasizing points with a halo or visual effect | Numeric x and y columns | Decoration should not substitute for an actual data encoding | [Example](../examples/effect_scatter/) · [API](../dataviz/effect_scatter/effect_scatter/) |
| Single axis | Showing values along one numeric dimension | One numeric position per observation | Coincident values overlap without another distinguishing channel | [Example](../examples/single_axis/) · [API](../dataviz/single_axis/single_axis/) |
| Correlation plot | Scanning pairwise correlations across variables | Variable names and a square correlation matrix | Correlation does not establish causation or expose nonlinear structure | [Example](../examples/corrplot/) · [API](../dataviz/corrplot/corrplot/) |
| Parallel coordinates | Comparing observations across many numeric dimensions | One value list per observation and dimension names | Axis order and scaling strongly affect visible patterns | [Example](../examples/parallel/) · [API](../dataviz/parallel/parallel/) |
| Radar | Comparing a few named profiles across common indicators | Indicators, maxima, series names, and values by series | Area and angle make precise cross-axis comparisons difficult | [Example](../examples/radar/) · [API](../dataviz/radar/radar/) |
| Polar line | Showing a relationship naturally expressed as angle and radius | Angle and radius columns | Cartesian alternatives are usually easier to read without a circular domain | [Example](../examples/polar/) · [API](../dataviz/polar/polar/) |
| Multi-series polar | Comparing several angle-radius paths | Angles, series names, and radius values by series | Multiple paths can overlap heavily | [Example](../examples/polar_series/) · [API](../dataviz/polar/polar_series/) |
| Wind barbs | Showing vector direction and magnitude at positions | x and y positions plus u and v vector components | Dense fields need enough canvas space to keep glyphs distinct | [Example](../examples/barbs/) · [API](../dataviz/barbs/barbs/) |

## Show composition and progress

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Stacked bar | Comparing category totals and their components | Categories, series names, and one value list per series | Interior segments are difficult to compare across bars | [Example](../examples/stacked_bar/) · [API](../dataviz/stacked_bar/stacked_bar/) |
| Pie or donut | Showing a small number of parts of one whole | Categories and non-negative values | Angles are hard to compare; avoid many similar slices | [Example](../examples/pie/) · [API](../dataviz/arc/pie/) |
| Marimekko | Showing two categorical proportions at once | Categories, subcategories, and a subcategory-by-category matrix | Both width and height vary, making exact comparison difficult | [Example](../examples/marimekko/) · [API](../dataviz/marimekko/marimekko/) |
| Funnel | Showing values across ordered process stages | Stage names and non-negative values | Width implies magnitude, not causal conversion between stages | [Example](../examples/funnel/) · [API](../dataviz/funnel/funnel/) |
| Gauge | Showing one value against a bounded target range | Value plus minimum and maximum | Space-inefficient for comparing many values | [Example](../examples/gauge/) · [API](../dataviz/gauge/gauge/) |
| Nightingale rose | Comparing magnitudes around a categorical circle | Categories and non-negative values | Radius can exaggerate area unless the intended scaling is clear | [Example](../examples/nightingale/) · [API](../dataviz/nightingale/nightingale/) |
| Polar bar | Comparing bars along an angular axis | Categories and non-negative values | Circular position makes ordinary category comparison harder | [Example](../examples/polarbar/) · [API](../dataviz/polar_bar/polarbar/) |
| Radial bar | Showing category progress around a circle | Categories and non-negative values | A linear bar is more precise when radial layout adds no meaning | [Example](../examples/radialbar/) · [API](../dataviz/radialbar/radialbar/) |

## Show hierarchies

All three hierarchy charts use flattened `ids`, `parent_ids`, and leaf
`values`. Exactly one row is the root.

| Chart | Use it when | Watch for | Links |
| --- | --- | --- | --- |
| Tree | Emphasizing parent-child structure | Deep or broad trees need substantial space | [Example](../examples/tree/) · [API](../dataviz/tree/tree/) |
| Treemap | Comparing leaf size within a hierarchy | Small rectangles leave little room for labels | [Example](../examples/treemap/) · [API](../dataviz/treemap/treemap/) |
| Sunburst | Showing hierarchy depth and part-to-whole size together | Outer arcs are harder to compare and label | [Example](../examples/sunburst/) · [API](../dataviz/sunburst/sunburst/) |

## Show flows and networks

These charts use parallel source, destination, and non-negative value columns.

| Chart | Use it when | Watch for | Links |
| --- | --- | --- | --- |
| Sankey | Tracing quantities through directed stages | The graph must be acyclic; crossing flows quickly add clutter | [Example](../examples/sankey/) · [API](../dataviz/sankey/sankey/) |
| Chord | Showing weighted connections among a moderate set of entities | Direction and exact values are difficult to compare in a dense circle | [Example](../examples/chord/) · [API](../dataviz/chord/chord/) |
| Arc diagram | Showing connections while preserving a meaningful node order | Long arcs can obscure local structure | [Example](../examples/arc_diagram/) · [API](../dataviz/arc_diagram/arc_diagram/) |
| Graph | Showing general relationships among nodes | The circular layout is deterministic but does not discover communities | [Example](../examples/graph/) · [API](../dataviz/graph/graph/) |

## Show grids, matrices, and fields

| Chart | Use it when | Required data | Watch for | Links |
| --- | --- | --- | --- | --- |
| Heatmap | Comparing values across two categorical dimensions | Long-form x, y, and value columns | Color supports pattern finding better than exact lookup | [Example](../examples/heatmap/) · [API](../dataviz/heatmap/heatmap/) |
| Image | Displaying a regular row-major numeric array | A rectangular `z[row][column]` matrix | Row zero appears at the top; size the plot deliberately when aspect matters | [Example](../examples/imshow/) · [API](../dataviz/image/imshow/) |
| Pseudocolor mesh | Displaying a matrix over unequal cell boundaries | x edges, y edges, and a rectangular matrix | Each edge list has one more entry than its matrix dimension | [Example](../examples/pcolormesh/) · [API](../dataviz/image/pcolormesh/) |
| Contour or filled contour | Showing levels across a regular sampled surface | x coordinates, y coordinates, and a rectangular grid | At least a 2-by-2 grid is required; level choices affect the story | [Line example](../examples/contour/) · [Filled example](../examples/contourf/) · [Line API](../dataviz/contour/contour/) · [Filled API](../dataviz/contour/contourf/) |
| Scattered contour | Estimating levels from irregularly positioned samples | x, y, values, and triangulation-compatible points | Sparse or poorly distributed points can create misleading triangles | [Line example](../examples/tricontour/) · [Filled example](../examples/tricontourf/) · [Line API](../dataviz/tricontour/tricontour/) · [Filled API](../dataviz/tricontour/tricontourf/) |
| Triangular mesh | Inspecting or coloring an irregular triangulation | Point x/y coordinates and, for color, one value per point | The Delaunay mesh quality depends on the point distribution | [Mesh example](../examples/triplot/) · [Color example](../examples/tripcolor/) · [Mesh API](../dataviz/triplot/triplot/) · [Color API](../dataviz/triplot/tripcolor/) |
| Punchcard | Comparing activity across two categorical cycles | Two categorical columns and values | Large category products produce many small cells | [Example](../examples/punchcard/) · [API](../dataviz/punchcard/punchcard/) |

When several charts could work, build the simplest two with the same data and
compare what becomes easiest to see. The [Examples gallery](../examples/)
provides the fastest side-by-side source and output reference.
