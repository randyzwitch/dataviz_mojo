# Contributing

Run changes through Pixi so they use the repository's pinned Mojo toolchain:

```sh
pixi run format
pixi run test-changed
pixi run example
pixi run example-quickstart
pixi run docs
```

Use `pixi run test` instead of `test-changed` before merging changes that
affect shared rendering, encoding, scale, or layout behavior.

## Public API docstrings

Public callables use this structure:

````text
"""One sentence that makes sense without the function name.

Important behavior, data shape, and constraints.

Args:
    parameter: What it controls and any caller-relevant constraints.

Returns:
    What the function returns and whether further rendering is required.

Raises:
    Error: A specific condition the caller can avoid or handle.

Example:
    ```mojo
    # Complete imports, main(), and output call.
    ```
"""
````

Omit `Raises:` when the callable has no specific caller-actionable error to
document. Do not add a generic statement merely because its Mojo signature
uses `raises`.

For chart functions registered in `scripts/_example_docstrings.mojo`, the
documentation build enforces the following contract:

- The first paragraph is a non-empty summary used as the Examples-page hook.
- `Args:` is non-empty and lists every signature parameter once, in order.
- `Returns:` is non-empty.
- At least one `Example:` contains a complete runnable Mojo program.
- Example code imports chart constructors and core plotting symbols from
  `dataviz`. Specialist symbols come from their named public modules, such as
  `dataviz.colors`, `dataviz.colormaps`, or `dataviz.histogram`; implementation
  modules such as `dataviz.plot` are not example entry points.
- Every rendered example sets a non-empty chart title; label meaningful axes.
- Each generated example writes beneath `docs/src/examples/` so its rendered
  output can appear beside the source.
- A page selecting a named example variant uses an existing heading.

The `Example:` program is extracted and executed verbatim by
`pixi run example`. Keep setup relevant to the feature and use data that makes
the documented behavior visible.

## Documentation layout

- `README.md` explains the project, installation, and development commands.
- `docs/src/quickstart.md` teaches the first-chart workflow.
- Public chart docstrings generate `docs/src/examples/` pages.
- `docs/cookbook_recipes/` contains complete task-oriented programs; its
  README describes their additional conventions.
- `mojo doc` generates the API reference from source docstrings.

Edit the source or recipe rather than generated Markdown in
`docs/src/examples/` and `docs/src/cookbook/`, or generated site output in
`docs/site/content/` and `docs/site/public/`. The tracked quickstart programs
under `docs/src/examples/quickstart/` are source files and should be edited
alongside the Quickstart.
