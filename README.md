# dataviz_mojo

Grammar-of-graphics-flavored chart building for Mojo — a fluent `Plot`
builder (`Plot().mark_point().encode(x=..., y=...)`), scales, themes,
and a growing set of mark types (scatter, line, bar, area, pie/donut,
lollipop, waterfall, box, candlestick, bullet, gantt, grouped bar,
stacked bar) across both a raster and an SVG backend, plus facets and
multi-series layering. 

Please note that this is heavily Claude-influenced, so I do not
guarantee consistency, logic, or design decisions matching any
particular reference library. If you know what you're doing and want
to contribute, let's chat!

See `ROADMAP.md` for exactly what's built vs. still open.

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

## Development

```sh
pixi run test      # tests/*.mojo
pixi run example   # examples/*.mojo, writes examples/out_*.{bmp,svg}
```

## License

MIT — see `LICENSE`.
