"""The settings every mark shares and no mark owns: the theme, the
titles, the tooltip policy, the axis transforms and overrides, the color
domain, and the two layering flags. `Plot` holds one as `_settings`
(#826); a renderer reads what it needs from it and never the `Plot`."""

from dataviz.core.axis_controls import _TickOverride
from dataviz.core.color_scale import _ColorDomainOverride
from dataviz.core.plot_fields import _DomainOverride, _LabelData
from dataviz.core.theme import Theme
from dataviz.core.tooltips import Tooltips


struct _ChartSettings(Copyable, Movable):
    """What `Plot`'s builder methods set that is not data and not one
    mark's own: everything a renderer reads besides its payload and the
    shared channels. A setting only one mark reads belongs in that
    mark's struct (#522), and `width`/`height` stay on `Plot`, where
    callers read them.
    """

    var theme: Theme
    var labels: _LabelData
    """The chart title, subtitle and axis titles, set via `labels()`."""
    var tooltips: Optional[Tooltips]
    """Set via `tooltips()`; `None` leaves `Theme.tooltips` in charge."""
    # Set via .scale_y_log()/.scale_x_log().
    var y_log: Bool
    var x_log: Bool
    # Set via .scale_y_symlog()/.scale_x_symlog(). The threshold is only
    # meaningful when the flag is set; both are carried onto the frame's
    # `LinearScale.is_symlog`/`symlog_linthresh` (#368).
    var y_symlog: Bool
    var x_symlog: Bool
    var y_symlog_linthresh: Float64
    var x_symlog_linthresh: Float64
    var x_time: Bool
    """Whether `_continuous.x` holds POSIX seconds that the axis should
    label as dates and times. Set by `encode_time()`; carried onto the
    frame's `LinearScale.is_time`, which is the only thing that reads
    it."""
    var x_tz_offset: Int
    """The offset from UTC, in seconds, of the timestamps in
    `_continuous.x`, so ticks land on local boundaries and read in the
    caller's zone."""
    # Set via .scale_x_domain()/.scale_y_domain().
    var x_domain: _DomainOverride
    var y_domain: _DomainOverride
    # Set via .scale_x_ticks()/.scale_y_ticks()/.scale_x_reverse()/
    # .scale_y_reverse()/.equal_aspect() (#368). All five reach the
    # continuous frame together as one `_AxisControls`; nothing else
    # reads them.
    var x_tick_override: _TickOverride
    var y_tick_override: _TickOverride
    var x_reversed: Bool
    var y_reversed: Bool
    var equal_aspect: Bool
    # Set via .scale_color_domain()/.scale_color_center(); read by every
    # continuous-color mark through `_color_scale_for()`.
    var color_domain: _ColorDomainOverride
    # Set only via a mark_*(horizontal=True) parameter; there is no
    # `.horizontal()` builder method, so this is only ever `True`
    # alongside a mark whose `mark_*()` reads it.
    var horizontal: Bool
    # Set via .secondary_axis(); render_layers()/render_layers_svg() only.
    # This layer's y values scale against a second, independent y-domain
    # drawn on the right edge. render() raises if it's set on a
    # standalone plot.
    var secondary_axis: Bool

    def __init__(out self):
        self.theme = Theme.default()
        self.labels = _LabelData()
        self.tooltips = None
        self.y_log = False
        self.x_log = False
        self.y_symlog = False
        self.x_symlog = False
        self.y_symlog_linthresh = 1.0
        self.x_symlog_linthresh = 1.0
        self.x_time = False
        self.x_tz_offset = 0
        self.x_domain = _DomainOverride()
        self.y_domain = _DomainOverride()
        self.x_tick_override = _TickOverride()
        self.y_tick_override = _TickOverride()
        self.x_reversed = False
        self.y_reversed = False
        self.equal_aspect = False
        self.color_domain = _ColorDomainOverride()
        self.horizontal = False
        self.secondary_axis = False

    def tooltip_policy(self) -> Tooltips:
        """The policy in force: `tooltips()`'s if it was called, else
        the theme's."""
        if self.tooltips:
            return self.tooltips.value()
        return self.theme.tooltips

    def tooltips_on(self, count: Int) -> Bool:
        """Whether the chart draws its tooltips, given that it would draw
        `count` of them. Every mark's renderer asks this once, with the
        number of data it titles, so `Tooltips.AUTO` means the same
        thing on every mark.

        Args:
            count: How many tooltips the chart would draw.

        Returns:
            True to draw them.
        """
        return self.tooltip_policy().draws(count, self.theme.auto_tooltip_limit)
