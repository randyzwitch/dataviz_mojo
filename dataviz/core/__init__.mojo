"""Infrastructure the marks draw against: scales, frames, text, color and
the small shared enums (#524).

Grouped apart from the chart families because it is a different axis
entirely -- none of it is a mark, and forcing it into a chart category
would say something false about what it is for.

Nothing is re-exported here. Call sites import the module they need
(`from dataviz.core.scale import LinearScale`), which keeps the
dependency visible at the point of use rather than hiding it behind a
package-level alias. The public surface is re-exported from
`dataviz/__init__.mojo` and is unchanged by this grouping (#524).
"""
