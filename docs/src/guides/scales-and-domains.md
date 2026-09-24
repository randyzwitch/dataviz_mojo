---
title: Scales and domains
weight: 10
---

A scale maps data values to positions or colors. Its **domain** is the data
range; its output range is determined by the chart's plot area. Dataviz
computes position domains from the data and adds padding where appropriate.

## The axis line is not the origin

A point or line chart pads its domain by 5% of the data's span on each
side, so that a point at the extreme does not sit half-clipped on the
frame. The consequence catches people out the first time.

For `x = [1.0 ... 10.0]` the span is 9, so the domain becomes about
`[0.55, 10.45]`. The y-axis line stands at x = 0.55. It is not x = 0 and
it is not x = 1, and nothing on the axis says otherwise, so the first
point does not sit where you would expect if you read the axis line as a
clean origin: it is not halfway between the axis and the "2" tick,
because the axis is not at 1.

The point is in the right place. The axis line is just the edge of the
padded domain, and the tick marks are the only things on the frame that
name a value.

Two ways to get an axis line that means something:

```mojo
.scale_x_domain(0.0, 10.0)   # the axis line is exactly 0
```

or a mark that baselines at zero. `mark_bar()` and `mark_area()` use a
different rule: their domain always includes zero, and the end that is
already zero is not padded, so zero stays an exact endpoint. A bar
chart's baseline really is zero, which is what makes bar lengths
comparable.

## Candlesticks on a time axis

`candlestick()` accepts `List[Morrow]` dates as well as string categories.
Dates use their real positions, so a Friday-to-Monday gap is three times a
Monday-to-Tuesday gap. Its candle width follows the median interval between
observations and is capped so neighboring bodies do not overlap.

```mojo
from dataviz import candlestick, save
from morrow import Morrow

def main() raises:
    var dates: List[Morrow] = [
        Morrow.get(2024, 3, 1),
        Morrow.get(2024, 3, 4),
        Morrow.get(2024, 3, 5),
    ]
    var open: List[Float64] = [10.0, 12.0, 14.0]
    var high: List[Float64] = [15.0, 16.0, 17.0]
    var low: List[Float64] = [8.0, 9.0, 11.0]
    var close: List[Float64] = [13.0, 14.0, 12.0]
    save(candlestick(dates, open, high, low, close), "candles.svg")
```

Padding applies to spatial axes only. Color and size domains are the
data's own minimum and maximum, so a legend's extremes are real values.

Use `.scale_x_domain(min, max)` or `.scale_y_domain(min, max)` when charts must
use a fixed reference range. Use `.scale_x_log()` or `.scale_y_log()` when
ratios matter more than absolute differences.

```mojo
from dataviz import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 10.0, 100.0, 1000.0]
    var y: List[Float64] = [2.0, 4.0, 8.0, 16.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .scale_x_log()
        .scale_y_domain(0.0, 20.0)
        .labels(title="Logarithmic X Scale", x_title="Frequency", y_title="Gain")
    )
    save(plot, "scale.svg")
```

Log-scaled values and annotation positions must be strictly positive. Log y is
not available for area marks because their domain includes zero. Explicit
domains apply to continuous-axis marks and facets; layered charts compute a
shared domain instead of accepting per-layer overrides.

See the [log-x](../../cookbook/log_scale_x/) and
[log-y](../../cookbook/log_scale_y/) recipes, and the
[`Plot` scale methods](../../dataviz/plot/Plot/).
