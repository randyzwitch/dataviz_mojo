# Contributing a Cookbook recipe

Cookbook recipes are standalone techniques, while gallery examples come from
public API docstrings. Add recipes directly to this directory.

## How it works

Add one self-contained `.mojo` file. `pixi run docs` discovers it automatically.

Your file must look like this:

```mojo
"""One or two sentences describing the technique -- this becomes the
Cookbook page's own hook line, shown right under its title. Anything
after the first sentence (further paragraphs, more detail) is fine to
include for your own documentation but won't appear on the page --
keep the important part first.
"""
from dataviz.plot import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [2.0, 5.0, 3.0]

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
    )
    save(plot, "docs/src/examples/out_<your_file_name>.svg")
```

Rules the build enforces:

- **The file's own leading `"""..."""` docstring is required** -- its
  first sentence becomes the page's hook text.
  Keep any `` `inline code span` `` in that first sentence on one
  source line -- the extraction joins hand-wrapped lines with a plain
  space, so a code span broken across a line wrap renders with a
  stray space in the middle (e.g. `` `Theme.\npoint_radius` `` would
  show up as "Theme. point_radius").
- **Everything after that docstring must be a complete, real, runnable
  program** -- real imports, a `def main() raises:`, and a real
  `save(...)`/`save_layers(...)`/`save_facets(...)`/
  `write_accessible_svg(...)` call writing to
  `docs/src/examples/out_<name>.svg`, matching the recipe filename.
  `pixi run example` compiles and runs every recipe.
- **The page's title is your filename, title-cased** -- `bold_points.
  mojo` becomes "Bold Points". Name your file the way you'd want the
  page titled. When that plain rule can't produce the title you
  actually want (an acronym like "SVG", a hyphenated compound like
  "High-DPI Export", a lowercase preposition like "Color by
  Category"), add a `# title: <text>` comment as the file's *very
  first line*, before your docstring -- it overrides the filename-
  derived title, and nothing else about the file changes.
- **Your filename must not collide with an existing Cookbook or
  Examples page name** -- the build raises a clear error if it does,
  rather than silently overwriting one page with another.

## What you get

`scripts/gen_example_docs.mojo` builds the title, introductory sentence,
usage block, and rendered image into `docs/src/cookbook/<name>.md`.

See `bold_points.mojo` in this same directory for a complete, real
example -- copy it as a starting template.
