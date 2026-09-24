# Interactive exploration scope (#373)

Decision recorded for the Mojo 1.1 workspace. Defer an interactive backend
until the host contract below can be exercised end to end. Keep static SVG,
raster, and PDF rendering as the supported output path. This decision does
not decide #108 (automatic display of a static chart).

## Initial host

Target a browser surface in a Python-backed Jupyter notebook first. Mojo's
[notebook documentation](https://mojolang.org/docs/tools/notebooks/) describes
`%%mojo` cells run through a Python kernel, with each cell containing a
complete `main()` program. That is a plausible way to create a plot, but the
documented cell interface does not establish a persistent browser-to-Mojo
event or object-lifetime contract. Treat that as an open integration question,
not as a supported callback API. A desktop window would add another host and
lifecycle before the notebook path is proven.

The package currently returns a rendered `Canvas` or `SvgCanvas`; it has no
host-owned figure object, observation identity mapping, or callback registry.
SVG `<title>` tooltips are useful output, but they cannot update a `Plot` or
report a pick to Mojo on their own.

## Contract for a first spike

Use one scatter plot. The host owns a figure instance with a stable figure ID,
a plot snapshot, view-domain state, and a monotonically increasing revision.
The core renderer remains callable without the host.

- **Zoom and pan:** store x and y domains in data units. Invert the current
  scale at the pointer, zoom both domain endpoints about that data coordinate,
  and pan by the difference between the inverted start and end pointer
  positions. Test linear axes first. Log, categorical, reversed, and shared
  axes need explicit inverse-scale rules before they can be enabled.
- **Picking:** an observation needs an ID independent of SVG element order and
  the current row position after filtering or sorting. A caller-supplied ID
  column is the clean boundary for table-backed plots; vector-backed plots
  can use their input index until data is replaced. The host maps a pointer
  hit to `(figure_id, revision, layer_id, observation_id, x, y)` and sends that
  value across the callback boundary. Stale revisions are ignored.
- **Data updates:** an update replaces the figure's data snapshot, increments
  the revision, and rerenders into the *same* host element. A view-only update
  keeps the data snapshot and changes its domains. The first spike may rerender
  the whole SVG for either operation; retained drawing and animation are out
  of scope. A disposal operation removes event handlers and the host element.
- **Headless use:** `render()`, `render_svg()`, `render_pdf()`, and `save()` must
  continue to work without a notebook, browser, event loop, or Python import.
  The browser adapter must be an optional layer over those functions.

## Why implementation is deferred

A demo made only of JavaScript pan/zoom over exported SVG would not prove a
pick reaches Mojo or that a Mojo data update replaces the existing figure.
The current notebook documentation demonstrates running complete Mojo
programs and printing their output; it does not specify the persistent event
and object-lifetime boundary the spike needs. The package also does not yet
retain stable observation IDs through rendering. Implementing controls before
those two contracts are settled would make a visually interactive demo with
no reliable path back to the data.

Resume with a small, testable host bridge that can (1) publish an SVG into one
notebook output element, (2) deliver a pointer event to a still-live Mojo
handler, and (3) replace that element from a new plot snapshot. Then measure
redraw latency for a specified scatter data size on one browser and machine,
and test zoom, pick, data replacement, disposal, and headless export. Record
supported notebook versions and platforms with that spike. Full GUI backend
parity and animation belong to later work.
