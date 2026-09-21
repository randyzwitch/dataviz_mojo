# Security policy

## Supported versions

This package is pre-1.0 and ships from `main` between tags. Fixes land on
`main` and go out in the next release; there are no backports to older
tags. Use the [latest release](https://github.com/randyzwitch/dataviz_mojo/releases/latest).

## Reporting a vulnerability

Report it privately through
[GitHub Security Advisories](https://github.com/randyzwitch/dataviz_mojo/security/advisories/new),
not a public issue. You will get an acknowledgment, and an advisory will be
published alongside the fix once one exists.

## What is in scope

This is a charting library: it turns data you supply into an image or a
document. The interesting cases are the ones where *data* reaches something
that should only be reachable by *code*.

- Malformed or hostile input data that crashes the process rather than
  raising, or that reads or writes outside a buffer. `save()`, the raster
  backend, and anything measuring text are the paths worth probing.
- Text that escapes its context in an output format -- a label that closes
  a tag and injects markup into an SVG, or that breaks out of a PDF string.
  SVG is the one to look at first, since a chart is often served directly
  to a browser.
- A path from a caller-supplied string to a file written somewhere other
  than the path given.

## What is not

- A chart that draws the wrong thing, or a call that raises when it should
  not. Those are bugs; please
  [file an issue](https://github.com/randyzwitch/dataviz_mojo/issues/new/choose).
- Rendering a font from the machine the code runs on. Resolving and
  embedding an installed font is what the raster and PDF backends are for.
- Vulnerabilities in dependencies. Report those upstream --
  [canvas_mojo](https://github.com/randyzwitch/canvas_mojo/security),
  [dataframe_mojo](https://github.com/randyzwitch/dataframe_mojo/security),
  or Mojo itself -- and tell us here if this package needs a pin bump.
