"""#732 bisect: run tests 8..16 of test_marks_polar, in order.

Compiling the module is not the trigger (only16: 0 crashes in 80) and
neither is the crashing test's body (repro: 0 in 80), so what the tests
before it do is. Each of these modules runs a suffix of that sequence,
ending with test 16. The shortest one that still crashes bounds
what is needed.

Generated for #732; delete with it.
"""

from std.sys import stderr

from test_marks_polar import (
    test_render_nightingale_matches_hand_derived_wedge_colors,
    test_render_nightingale_area_mode_scales_radius_by_sqrt,
    test_render_nightingale_svg_matches_confirmed_wedge_paths,
    test_render_nightingale_raises_on_negative_value,
    test_render_nightingale_raises_on_all_zero_values,
    test_render_nightingale_raises_on_mismatched_category_length,
    test_render_nightingale_raises_on_no_data,
    test_render_polar_matches_hand_derived_line_and_markers,
    test_render_polar_draws_a_grid_even_with_no_data_on_it,
)


def main() raises:
    print("START 8 test_render_nightingale_matches_hand_derived_wedge_colors", file=stderr)
    test_render_nightingale_matches_hand_derived_wedge_colors()
    print("START 9 test_render_nightingale_area_mode_scales_radius_by_sqrt", file=stderr)
    test_render_nightingale_area_mode_scales_radius_by_sqrt()
    print("START 10 test_render_nightingale_svg_matches_confirmed_wedge_paths", file=stderr)
    test_render_nightingale_svg_matches_confirmed_wedge_paths()
    print("START 11 test_render_nightingale_raises_on_negative_value", file=stderr)
    test_render_nightingale_raises_on_negative_value()
    print("START 12 test_render_nightingale_raises_on_all_zero_values", file=stderr)
    test_render_nightingale_raises_on_all_zero_values()
    print("START 13 test_render_nightingale_raises_on_mismatched_category_length", file=stderr)
    test_render_nightingale_raises_on_mismatched_category_length()
    print("START 14 test_render_nightingale_raises_on_no_data", file=stderr)
    test_render_nightingale_raises_on_no_data()
    print("START 15 test_render_polar_matches_hand_derived_line_and_markers", file=stderr)
    test_render_polar_matches_hand_derived_line_and_markers()
    print("START 16 test_render_polar_draws_a_grid_even_with_no_data_on_it", file=stderr)
    test_render_polar_draws_a_grid_even_with_no_data_on_it()
    print("ALL DONE", file=stderr)
