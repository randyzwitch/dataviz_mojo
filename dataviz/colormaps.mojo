"""The perceptually uniform sequential colormaps (#332).

Each function returns a `List[Color]` for `Theme.color_ramp`, which
`ColorScale.from_theme` spreads evenly over `[0, 1]`:

```mojo
from dataviz.colormaps import viridis
from dataviz.theme import Theme

var theme = Theme(color_ramp=viridis())
```

**Why these and not a gradient of your own.** A ramp built by
interpolating two or three colors is almost never perceptually uniform:
it will have stretches where a large change in the data barely changes
the color, and stretches where a small one jumps. The reader sees
structure that is not in the data, and misses structure that is. These
five maps are constructed so that equal steps in the value look like
equal steps in color, and so that lightness increases monotonically --
which is also what makes them survive being printed in grayscale.

**Provenance.** The stops are sampled from matplotlib's canonical
256-entry tables. viridis, magma, inferno and plasma were created by
Nathaniel Smith and Stefan van der Walt and released under CC0; cividis
by Jamie Nunez, Sean Colby and Ryan Renslow, also CC0. Both are public
domain dedications, so the tables are reproduced here directly.

**Why 64 stops rather than all 256.** 64 is `ColorRamp`'s capacity --
see that struct for why the stops have to live in a fixed-width vector
-- so these tables fill it exactly. Sampling `ColorScale.from_theme` at
all 256 positions and comparing against matplotlib 3.11.1's own
256-entry tables gives a maximum error of **2 levels per channel out of
255** for every one of the five, a mean of 0.19 to 0.30, and exact
endpoints. That is below a perceptible step.

The entries are matplotlib's own colors at those positions rather than a
least-squares fit to the curve. A fit measures very slightly better but
produces colors that appear nowhere in the reference, which would make
these tables impossible to check. As written, any single entry can be
verified against matplotlib one line at a time.
"""

from canvas.color import Color


def viridis() -> List[Color]:
    """Viridis: dark blue-purple through green to yellow. Matplotlib's
    default sequential map since 2.0, and the usual first choice for
    data that runs low to high.

    Designed by Nathaniel Smith and Stefan van der Walt to be
    perceptually uniform -- equal steps in the data look like equal
    steps in color -- and to stay monotonic in lightness, so it also
    reads correctly printed in grayscale and to a color-blind viewer.

    Returns:
        64 stops, for `Theme(color_ramp=viridis())`."""
    return [
        Color(68, 1, 84),
        Color(70, 7, 90),
        Color(71, 13, 96),
        Color(71, 19, 101),
        Color(72, 24, 106),
        Color(72, 29, 111),
        Color(72, 35, 116),
        Color(72, 40, 120),
        Color(71, 45, 123),
        Color(70, 50, 126),
        Color(69, 55, 129),
        Color(67, 61, 132),
        Color(66, 65, 134),
        Color(64, 70, 136),
        Color(62, 74, 137),
        Color(60, 79, 138),
        Color(58, 83, 139),
        Color(56, 88, 140),
        Color(54, 92, 141),
        Color(52, 96, 141),
        Color(50, 100, 142),
        Color(49, 104, 142),
        Color(47, 108, 142),
        Color(45, 112, 142),
        Color(44, 115, 142),
        Color(42, 119, 142),
        Color(41, 123, 142),
        Color(39, 127, 142),
        Color(38, 130, 142),
        Color(36, 134, 142),
        Color(35, 138, 141),
        Color(33, 142, 141),
        Color(32, 146, 140),
        Color(31, 150, 139),
        Color(31, 154, 138),
        Color(31, 158, 137),
        Color(31, 161, 135),
        Color(33, 165, 133),
        Color(35, 169, 131),
        Color(38, 173, 129),
        Color(42, 176, 127),
        Color(47, 180, 124),
        Color(53, 183, 121),
        Color(59, 187, 117),
        Color(66, 190, 113),
        Color(74, 193, 109),
        Color(82, 197, 105),
        Color(90, 200, 100),
        Color(99, 203, 95),
        Color(108, 205, 90),
        Color(117, 208, 84),
        Color(127, 211, 78),
        Color(137, 213, 72),
        Color(149, 216, 64),
        Color(160, 218, 57),
        Color(170, 220, 50),
        Color(181, 222, 43),
        Color(192, 223, 37),
        Color(202, 225, 31),
        Color(213, 226, 26),
        Color(223, 227, 24),
        Color(234, 229, 26),
        Color(244, 230, 30),
        Color(253, 231, 37),
    ]


def magma() -> List[Color]:
    """Magma: near-black through purple and red to pale yellow. From the
    same family as `viridis` and equally uniform, but with a dark end
    rather than a saturated one, which suits a dense image or a heatmap
    where the low values should recede.

    Returns:
        64 stops, for `Theme(color_ramp=magma())`."""
    return [
        Color(0, 0, 4),
        Color(2, 1, 9),
        Color(3, 3, 18),
        Color(6, 5, 26),
        Color(10, 8, 34),
        Color(14, 11, 43),
        Color(19, 13, 52),
        Color(24, 15, 61),
        Color(29, 17, 71),
        Color(34, 17, 80),
        Color(41, 17, 90),
        Color(49, 17, 101),
        Color(56, 16, 108),
        Color(63, 15, 114),
        Color(69, 16, 119),
        Color(76, 17, 122),
        Color(82, 19, 124),
        Color(89, 21, 126),
        Color(95, 24, 127),
        Color(101, 26, 128),
        Color(107, 29, 129),
        Color(114, 31, 129),
        Color(120, 34, 129),
        Color(126, 36, 130),
        Color(132, 38, 129),
        Color(139, 41, 129),
        Color(145, 43, 129),
        Color(152, 45, 128),
        Color(158, 47, 127),
        Color(165, 49, 126),
        Color(171, 51, 124),
        Color(178, 53, 123),
        Color(186, 56, 120),
        Color(192, 58, 118),
        Color(199, 61, 115),
        Color(205, 64, 113),
        Color(211, 67, 110),
        Color(217, 70, 107),
        Color(223, 74, 104),
        Color(228, 79, 100),
        Color(233, 84, 98),
        Color(237, 90, 95),
        Color(241, 96, 93),
        Color(244, 103, 92),
        Color(246, 110, 92),
        Color(248, 118, 92),
        Color(250, 125, 94),
        Color(251, 133, 96),
        Color(252, 140, 99),
        Color(253, 148, 103),
        Color(253, 155, 107),
        Color(254, 163, 111),
        Color(254, 170, 116),
        Color(254, 180, 123),
        Color(254, 187, 129),
        Color(254, 194, 135),
        Color(254, 202, 141),
        Color(254, 209, 148),
        Color(254, 216, 154),
        Color(253, 224, 161),
        Color(253, 231, 169),
        Color(252, 238, 176),
        Color(252, 246, 184),
        Color(252, 253, 191),
    ]


def inferno() -> List[Color]:
    """Inferno: `magma`'s higher-contrast sibling, black through red to a
    near-white yellow. The widest lightness range of the family, so it
    separates the top end more strongly at the cost of a harsher look.

    Returns:
        64 stops, for `Theme(color_ramp=inferno())`."""
    return [
        Color(0, 0, 4),
        Color(2, 1, 10),
        Color(4, 3, 18),
        Color(7, 5, 27),
        Color(11, 7, 36),
        Color(16, 9, 45),
        Color(21, 11, 55),
        Color(27, 12, 65),
        Color(33, 12, 74),
        Color(40, 11, 83),
        Color(47, 10, 91),
        Color(56, 9, 98),
        Color(62, 9, 102),
        Color(69, 10, 105),
        Color(76, 12, 107),
        Color(82, 14, 109),
        Color(89, 16, 110),
        Color(95, 19, 110),
        Color(101, 21, 110),
        Color(108, 24, 110),
        Color(114, 26, 110),
        Color(120, 28, 109),
        Color(127, 30, 108),
        Color(133, 33, 107),
        Color(140, 35, 105),
        Color(146, 37, 104),
        Color(152, 39, 102),
        Color(159, 42, 99),
        Color(165, 44, 96),
        Color(171, 47, 94),
        Color(177, 50, 90),
        Color(183, 53, 87),
        Color(191, 57, 82),
        Color(196, 60, 78),
        Color(202, 64, 74),
        Color(207, 68, 70),
        Color(212, 72, 66),
        Color(217, 77, 61),
        Color(222, 82, 56),
        Color(226, 87, 52),
        Color(230, 93, 47),
        Color(234, 99, 42),
        Color(237, 105, 37),
        Color(240, 111, 32),
        Color(243, 118, 27),
        Color(245, 125, 21),
        Color(247, 132, 16),
        Color(249, 139, 11),
        Color(250, 146, 7),
        Color(251, 153, 6),
        Color(252, 161, 8),
        Color(252, 168, 13),
        Color(252, 176, 20),
        Color(251, 186, 31),
        Color(250, 194, 40),
        Color(249, 201, 50),
        Color(247, 209, 61),
        Color(245, 217, 73),
        Color(244, 225, 86),
        Color(242, 232, 101),
        Color(241, 239, 117),
        Color(243, 245, 134),
        Color(246, 250, 150),
        Color(252, 255, 164),
    ]


def plasma() -> List[Color]:
    """Plasma: blue through magenta to yellow, with no dark end. Uniform
    like the rest of the family but starting mid-lightness, which keeps
    the low values legible instead of sinking them into the background
    -- useful when zero is a real value rather than absence.

    Returns:
        64 stops, for `Theme(color_ramp=plasma())`."""
    return [
        Color(13, 8, 135),
        Color(25, 6, 140),
        Color(34, 6, 144),
        Color(42, 5, 147),
        Color(49, 5, 151),
        Color(56, 4, 154),
        Color(63, 4, 156),
        Color(70, 3, 159),
        Color(76, 2, 161),
        Color(83, 2, 163),
        Color(89, 1, 165),
        Color(97, 0, 167),
        Color(103, 0, 168),
        Color(110, 0, 168),
        Color(116, 1, 168),
        Color(122, 2, 168),
        Color(128, 4, 168),
        Color(134, 6, 166),
        Color(139, 10, 165),
        Color(145, 14, 163),
        Color(150, 19, 161),
        Color(156, 23, 158),
        Color(161, 27, 155),
        Color(166, 32, 152),
        Color(171, 36, 148),
        Color(176, 41, 145),
        Color(180, 46, 141),
        Color(184, 50, 137),
        Color(189, 55, 134),
        Color(193, 59, 130),
        Color(197, 64, 126),
        Color(201, 68, 122),
        Color(205, 74, 118),
        Color(209, 78, 114),
        Color(213, 83, 111),
        Color(216, 87, 107),
        Color(219, 92, 104),
        Color(222, 97, 100),
        Color(226, 101, 97),
        Color(229, 106, 93),
        Color(231, 111, 90),
        Color(234, 116, 87),
        Color(237, 121, 83),
        Color(239, 126, 80),
        Color(241, 131, 76),
        Color(244, 136, 73),
        Color(246, 141, 69),
        Color(247, 147, 66),
        Color(249, 152, 62),
        Color(250, 158, 59),
        Color(252, 163, 56),
        Color(252, 169, 52),
        Color(253, 175, 49),
        Color(254, 183, 45),
        Color(254, 189, 42),
        Color(253, 195, 40),
        Color(253, 202, 38),
        Color(252, 208, 37),
        Color(251, 215, 36),
        Color(249, 221, 37),
        Color(247, 228, 37),
        Color(245, 235, 39),
        Color(242, 242, 39),
        Color(240, 249, 33),
    ]


def cividis() -> List[Color]:
    """Cividis: viridis reworked by Jamie Nunez, Sean Colby and Ryan
    Renslow so that a viewer with deuteranomaly or protanomaly sees
    very nearly what everyone else does, rather than an approximation
    of it. Blue through gray-green to yellow.

    Prefer it over `viridis` when the chart has to work for every
    reader and cannot be checked with them first.

    Returns:
        64 stops, for `Theme(color_ramp=cividis())`."""
    return [
        Color(0, 34, 78),
        Color(0, 37, 84),
        Color(0, 40, 91),
        Color(0, 43, 98),
        Color(0, 46, 106),
        Color(0, 48, 112),
        Color(5, 51, 113),
        Color(18, 53, 112),
        Color(26, 56, 111),
        Color(33, 59, 110),
        Color(39, 62, 110),
        Color(46, 65, 109),
        Color(51, 68, 109),
        Color(56, 71, 108),
        Color(60, 74, 108),
        Color(64, 76, 108),
        Color(68, 79, 108),
        Color(72, 82, 108),
        Color(76, 85, 108),
        Color(80, 87, 108),
        Color(84, 90, 109),
        Color(87, 93, 109),
        Color(91, 96, 110),
        Color(94, 99, 111),
        Color(98, 101, 111),
        Color(101, 104, 112),
        Color(105, 107, 113),
        Color(108, 110, 114),
        Color(112, 113, 115),
        Color(115, 116, 117),
        Color(119, 119, 118),
        Color(122, 122, 120),
        Color(126, 125, 120),
        Color(130, 128, 121),
        Color(134, 131, 121),
        Color(138, 134, 120),
        Color(142, 137, 120),
        Color(146, 140, 120),
        Color(149, 143, 119),
        Color(153, 146, 119),
        Color(157, 149, 118),
        Color(161, 153, 117),
        Color(165, 156, 116),
        Color(169, 159, 115),
        Color(173, 162, 114),
        Color(177, 165, 112),
        Color(182, 169, 111),
        Color(186, 172, 109),
        Color(190, 175, 107),
        Color(194, 179, 105),
        Color(198, 182, 103),
        Color(203, 185, 101),
        Color(207, 189, 98),
        Color(212, 193, 95),
        Color(217, 197, 92),
        Color(221, 200, 88),
        Color(225, 204, 85),
        Color(230, 208, 81),
        Color(234, 211, 76),
        Color(239, 215, 72),
        Color(243, 219, 66),
        Color(248, 223, 60),
        Color(253, 227, 52),
        Color(254, 232, 56),
    ]
