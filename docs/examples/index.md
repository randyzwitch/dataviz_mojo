# Examples

Every example below is a complete, runnable `.mojo` file in this repo's own `examples/` directory -- each page shows its full source next to its actual rendered output, so you can see exactly what it takes to produce that chart.

All of them share one pattern: build a `Plot`, `.encode()` your data onto it, optionally `.theme()`/`.labels()` it, then hand it to `render()` (raster) or `render_svg()` (vector).

## Basic marks

The core chart types -- one mark, default theme.

- [Scatter](scatter.md)
- [Line](line.md)
- [Bar](bar.md)
- [Area](area.md)
- [Pie](pie.md)

## Data-driven encoding

Mapping a data column onto color and/or size, not just position.

- [Categorical Color](categorical_color.md)
- [Bubble Chart](bubble.md)
- [Donut](donut.md)

## Smoothing

Catmull-Rom curve smoothing for LINE and AREA marks.

- [Line Smoothing](line_smoothing.md)
- [Area Smoothing](area_smoothing.md)

## Categorical business charts

Chart types built for a categorical x-axis: rankings, timelines, progress.

- [Lollipop](lollipop.md)
- [Waterfall](waterfall.md)
- [Gantt](gantt.md)
- [Bullet](bullet.md)
- [Diverging Bar](diverging_bar.md)
- [Grouped Bar](grouped_bar.md)
- [Stacked Bar](stacked_bar.md)

## Statistical & financial

Distributions, binned counts, and OHLC price data.

- [Box Plot](box.md)
- [Histogram](histogram.md)
- [Candlestick](candlestick.md)

## Layout & composition

Multiple plots, titles, and margin behavior beyond a single chart.

- [Facets](facets.md)
- [Layers](layers.md)
- [Titles & Axis Labels](titles.md)
- [Dynamic Left Margin](dynamic_margin.md)
- [Slope](slope.md)

## SVG backend

The same charts rendered through SvgCanvas instead of Canvas.

- [Scatter (SVG)](scatter_svg.md)
- [Facets (SVG)](facets_svg.md)