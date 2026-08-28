---
title: dataviz_mojo
type: docs
weight: 100
---

Grammar-of-graphics-flavored chart building for Mojo — a
[fluent](https://martinfowler.com/bliki/FluentInterface.html) `Plot`
builder (`Plot().mark_point().encode(x=..., y=...)`), scales, themes,
and a growing set of mark types (scatter, line, bar, area, pie/donut,
lollipop, waterfall, box, candlestick, bullet, gantt, grouped bar,
stacked bar) across both a raster and an SVG backend, plus facets and
multi-series layering. 

Please note that this is heavily Claude-influenced, so I do not
guarantee consistency, logic, or design decisions matching any
particular reference library. If you know what you're doing and want
to contribute, let's chat!

**Start here:** [Examples](examples/) shows every chart type this
package can produce, source code next to its actual rendered output.
For the full API surface (every method `Plot`/`Theme` expose, every
scale, every mark), see the [`dataviz_mojo` package
reference](dataviz_mojo/). For what's built vs. still open and why,
see the [wiki](https://github.com/randyzwitch/dataviz_mojo/wiki)
([Changelog](https://github.com/randyzwitch/dataviz_mojo/wiki/Changelog)
/ [Backlog](https://github.com/randyzwitch/dataviz_mojo/wiki/Backlog)).

## Install

```toml
[workspace]
preview = ["pixi-build"]  # git-source pixi dependencies are still a preview feature

[dependencies]
dataviz_mojo = { git = "https://github.com/randyzwitch/dataviz_mojo.git", branch = "main" }
```

`pixi install`/`pixi run` builds `dataviz_mojo` (and its own
`canvas_mojo` dependency, transitively, the identical way) from that
git ref and installs the resulting precompiled package into your own
workspace's pixi environment — Mojo's own toolchain finds it there
automatically, no `-I` flag needed for either package.

## A first chart

```mojo
from dataviz_mojo import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1]

    var plot = Plot().mark_point().encode(x=x, y=y)
    save(plot, "chart.svg")
```

See [Examples](examples/) for the same pattern applied to every mark
type this package supports, plus color/size encoding, facets,
multi-series layering, and the SVG backend.

## Development

```sh
pixi run test      # tests/*.mojo
pixi run example   # examples/*.mojo, writes examples/out_*.{bmp,png,svg}
pixi run docs      # regenerates this site -- run `example` first
```

## License

MIT — see [`LICENSE`](https://github.com/randyzwitch/dataviz_mojo/blob/main/LICENSE).
