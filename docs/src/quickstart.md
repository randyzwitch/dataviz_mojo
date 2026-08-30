---
title: Quickstart
type: docs
weight: 100
---

# Quickstart

Get `dataviz_mojo` installed and render your first chart in a couple of minutes.

## Install

Add it to your workspace's `pixi.toml` as a git-source dependency:

```toml
[workspace]
preview = ["pixi-build"]  # git-source pixi dependencies are still a preview feature

[dependencies]
dataviz_mojo = { git = "https://github.com/randyzwitch/dataviz_mojo.git", branch = "main" }
```

`pixi install`/`pixi run` builds `dataviz_mojo` (and its own
`canvas_mojo` dependency, transitively, the identical way) from that
git ref and installs the resulting precompiled package into your own
workspace's pixi environment -- Mojo's own toolchain finds it there
automatically, no `-I` flag needed for either package.

## A first chart

```mojo
from dataviz_mojo import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1]

    var plot = (Plot()
               .mark_point()
               .encode(x=x, y=y)
               )
    save(plot, "chart.svg")
```

`Plot` is the same fluent builder behind every chart type this
package supports -- swap `.mark_point()` for `.mark_bar()`,
`.mark_line()`, `.mark_pie()`, and so on, and `encode()` for
whatever that mark needs. Most chart types also have a one-call
convenience function (`bar(categories, values)`, `scatter(x, y)`, ...)
built on top of `Plot` for the common case -- see the
[Examples](../examples/) gallery for the full pattern applied to every
mark, plus color/size encoding, facets, multi-series layering, and
theming.

`save()` picks the output backend from the file extension --
`.svg` for the SVG backend, `.png`/`.bmp` for the raster backend.

## Where to next

- **[Examples](../examples/)** -- every chart type this package can
  produce, source code next to its actual rendered output.
- **[API reference](../dataviz_mojo/)** -- the full surface `Plot`
  and `Theme` expose, every scale, every mark.
- **[Wiki](https://github.com/randyzwitch/dataviz_mojo/wiki)** -- what's
  built vs. still open and why
  ([Changelog](https://github.com/randyzwitch/dataviz_mojo/wiki/Changelog)
  / [Backlog](https://github.com/randyzwitch/dataviz_mojo/wiki/Backlog)).

## Developing dataviz_mojo itself

Working on the package rather than just using it:

```sh
pixi run test      # tests/*.mojo
pixi run example   # every dataviz_mojo/*.mojo `Example:` docstring section, writes docs/src/examples/out_*.svg
pixi run docs      # regenerates this site -- run `example` first
```

## License

MIT -- see [`LICENSE`](https://github.com/randyzwitch/dataviz_mojo/blob/main/LICENSE).
