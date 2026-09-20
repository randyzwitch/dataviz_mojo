"""#732 discriminator: compile the whole module, run only the test that
crashes.

The standalone repro (zz_repro_732.mojo) never crashed in 80 runs, but
the probe, which calls the same test out of test_marks_polar, crashed 25
times in the same run. So either compiling the whole module is part of
the recipe, or the 16 tests that run first are.

This imports the module -- so everything compiles -- and runs test 16
alone, 40 times. Crashes here mean the compile is what matters; a clean
sweep means the preceding tests are.

Delete with #732.
"""
from std.sys import stderr

from test_marks_polar import (
    test_render_polar_draws_a_grid_even_with_no_data_on_it,
)


def main() raises:
    for i in range(40):
        print("iter", i, file=stderr)
        test_render_polar_draws_a_grid_even_with_no_data_on_it()
    print("ALL DONE", file=stderr)
