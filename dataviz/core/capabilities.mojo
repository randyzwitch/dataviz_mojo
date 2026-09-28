"""What a mark honors and how it draws, as plain values (#829, #854).
The `MarkType` trait carries the same facts as comptime constants; this
is their runtime form for the checks that cannot see the type."""


struct _Capabilities(Copyable, ImplicitlyCopyable, Movable):
    """What a mark honors, as values: the trait's `supports_*` constants,
    and the drawing facts after them (`continuous_path`, `layerable`,
    ...; see the trait for each), read off a mark type by
    `_capabilities_of_type[M]()` (mark_type.mojo), so the checks that
    run at render time (theme-driven flags, settings chosen before the
    mark, erased charts) ask the same source the compile-time `where`
    clauses do (#829, #854)."""

    var tooltips: Bool
    var data_labels: Bool
    var horizontal: Bool
    var annotations_y: Bool
    var annotations_x: Bool
    var annotations_xy: Bool
    var log_x: Bool
    var log_y: Bool
    var color_size: Bool
    var straight_edged: Bool
    var continuous_path: Bool
    var layerable: Bool
    var color_is_value: Bool
    var categorical_bars: Bool
    var bar_combo_overlay: Bool
    var continuous_error_bars: Bool

    def __init__(out self):
        self.tooltips = False
        self.data_labels = False
        self.horizontal = False
        self.annotations_y = False
        self.annotations_x = False
        self.annotations_xy = False
        self.log_x = False
        self.log_y = False
        self.color_size = False
        self.straight_edged = False
        self.continuous_path = False
        self.layerable = False
        self.color_is_value = False
        self.categorical_bars = False
        self.bar_combo_overlay = False
        self.continuous_error_bars = False
