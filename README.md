# dataviz_mojo

Grammar-of-graphics-style chart building for Mojo: a fluent `Plot` builder,
scales, themes, raster and SVG output, facets, and multi-series layers.

See the **[documentation and examples](https://randyzwitch.com/dataviz_mojo/)**
for rendered examples and the generated API reference.

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

Pixi builds `dataviz_mojo` and its `canvas_mojo` dependency from the selected
Git ref. The package installs as `dataviz_mojo` and imports as `dataviz`:

```mojo
from dataviz import Plot, save
```

For a complete first chart and the command that runs it, follow the
**[five-minute quickstart](https://randyzwitch.com/dataviz_mojo/quickstart/)**.

## Development

```sh
pixi run test      # tests/*.mojo
pixi run example   # every dataviz/*.mojo `Example:` docstring section, writes docs/src/examples/out_*.svg
pixi run docs      # regenerates docs/ (served via GitHub Pages) -- run `example` first
pixi run bench     # render-time table per mark family at increasing sizes; add --check to fail on suspect scaling
pixi run format         # reformat source with mojo format
pixi run format-check   # fail if source isn't formatter-clean (what CI runs)
```

GitHub Actions builds documentation for pull requests and deploys it from
`main`. Use `pixi run docs` for a local preview.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the public-docstring template and
the checks run before a chart example is generated.

### Releasing

`pixi.toml` carries the version in two places, `[workspace].version`
and `[package].version`, which must agree (CI's `check-version` job
checks this on every push/PR). `pixi run release <version>` bumps both
together, commits, and tags:

```sh
pixi run release 0.8.0        # bumps, commits, tags v0.8.0 locally
git push origin main --tags   # review with `git show`/`git log` first
```

`pixi run check-version` on its own just checks the two fields agree;
pass a ref/tag as an extra argument (`pixi run check-version v0.8.0`)
to also check it against them. See `scripts/release.sh`/
`scripts/check_version.sh` for the full behavior. The wiki
[Changelog](https://github.com/randyzwitch/dataviz_mojo/wiki/Changelog)
stays the human-readable release record; update it separately.

## License

MIT — see `LICENSE`.
