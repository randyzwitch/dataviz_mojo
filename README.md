# dataviz_mojo

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

**[Docs & examples](https://randyzwitch.com/dataviz_mojo/)** --
every example's source next to its actual rendered output, plus the
full `dataviz_mojo` API reference (generated from this repo's own
docstrings via [modo](https://github.com/mlange-42/modo), see
`modo.yaml`/`pixi run docs`).

See the [wiki](https://github.com/randyzwitch/dataviz_mojo/wiki) for
exactly what's built ([Changelog](https://github.com/randyzwitch/dataviz_mojo/wiki/Changelog))
vs. still open ([Backlog](https://github.com/randyzwitch/dataviz_mojo/wiki/Backlog)).

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
pixi run example   # every dataviz_mojo/*.mojo `Example:` docstring section, writes docs/src/examples/out_*.svg
pixi run docs      # regenerates docs/ (served via GitHub Pages) -- run `example` first
```

`docs/` also regenerates and deploys itself automatically to GitHub
Pages (`.github/workflows/docs-deploy.yml`) whenever a push to `main`
touches `dataviz_mojo/` or `docs/_src/` -- manual
`pixi run docs` is for previewing locally before you push, not
required to keep the site in sync. PRs get a status-only docs build
(the `docs-build` job in `.github/workflows/ci.yml`) that proves the
site still builds, without deploying anything.

## License

MIT — see `LICENSE`.
