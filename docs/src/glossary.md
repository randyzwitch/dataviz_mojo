---
title: Glossary
type: docs
weight: 180
---

## Chart vocabulary

**Annotation**
: Explanatory content placed in data coordinates, such as a reference line,
  band, point, arrow, or fitted trend.

**Axis**
: The visible line, ticks, labels, and title that communicate a positional
  scale.

**Channel**
: A visual property that can carry data, such as x-position, y-position,
  color, size, shape, or text.

**Domain**
: The input values covered by a scale. A numeric x-domain might run from 0 to
  100; a categorical domain is an ordered set of names.

**Encoding**
: A mapping from a data column to a visual channel. For example,
  `encode(x=year, y=revenue)` maps two columns to position.

**Facet**
: One cell in a grid of independent plots. Facets may use independent scales
  or a supported shared y-scale.

**Layer**
: One plot drawn in the same coordinate frame as other plots. Compatible
  layers share an x-domain and either a primary or secondary y-axis.

**Legend**
: A key connecting colors, sizes, shapes, or named layers to their meaning.

**Mark**
: The geometric form used to represent data, such as a point, line, bar,
  area, box, or arc.

**Plot**
: The builder value containing a mark, encoded data, labels, annotations,
  scale settings, theme, and output size.

**Raster**
: Pixel-based output. Dataviz writes PNG and BMP raster files.

**Scale**
: A mapping from a data domain to a visual range, such as numeric values to
  pixel positions or colors.

**Secondary axis**
: An independent y-scale drawn on the right side of a layered chart for a
  series with different units.

**Theme**
: Presentation settings for canvas, axes, typography, marks, legends,
  annotations, and output.

**SVG**
: Vector output represented as XML shapes and text. It scales cleanly and can
  include accessibility metadata and tooltips.

Continue with the [Guides](../guides/), browse chart types in
[Examples](../examples/), or look up exact contracts in the
[API reference](../dataviz/).
