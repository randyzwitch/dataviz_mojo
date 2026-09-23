"""Named qualitative palettes for `Theme.categorical_palette`.

Use `Theme(categorical_palette=okabe_ito())` to select a palette explicitly.
The default uses the same eight colors; `tab10_legacy()` preserves the
previous order and colors for charts that need their earlier appearance.

Okabe and Ito's Color Universal Design palette:
https://jfly.uni-koeln.de/color/
Paul Tol's qualitative schemes (2021, figures 1, 4, and 7):
https://sronpersonalpages.nl/~pault/data/colourschemes.pdf
Tableau 10 palette redesign:
https://www.tableau.com/blog/colors-upgrade-tableau-10-56782
"""

from canvas.color import Color


def okabe_ito() -> List[Color]:
    """Eight Color Universal Design colors, ordered for chart series.

    Dark blue and vermilion lead because thin blue and yellow marks are
    harder to see on white; the light sky blue and yellow follow later.
    The set is Okabe and Ito's, with its order chosen for cycling.
    """
    return [
        Color(0, 114, 178),
        Color(213, 94, 0),
        Color(0, 158, 115),
        Color(204, 121, 167),
        Color(230, 159, 0),
        Color(86, 180, 233),
        Color(240, 228, 66),
        Color(0, 0, 0),
    ]


def tableau_10() -> List[Color]:
    """The redesigned Tableau 10 categorical palette."""
    return [
        Color(78, 121, 167),
        Color(242, 142, 43),
        Color(225, 87, 89),
        Color(118, 183, 178),
        Color(89, 161, 79),
        Color(237, 201, 72),
        Color(176, 122, 161),
        Color(255, 157, 167),
        Color(156, 117, 95),
        Color(186, 176, 172),
    ]


def tol_bright() -> List[Color]:
    """Paul Tol's seven-color bright scheme for lines and labels."""
    return [
        Color(68, 119, 170),
        Color(238, 102, 119),
        Color(34, 136, 51),
        Color(204, 187, 68),
        Color(102, 204, 238),
        Color(170, 51, 119),
        Color(187, 187, 187),
    ]


def tol_muted() -> List[Color]:
    """Paul Tol's nine-color muted scheme for maps and larger series."""
    return [
        Color(204, 102, 119),
        Color(51, 34, 136),
        Color(221, 204, 119),
        Color(17, 119, 51),
        Color(136, 204, 238),
        Color(136, 34, 85),
        Color(68, 170, 153),
        Color(153, 153, 51),
        Color(170, 68, 153),
    ]


def tol_light() -> List[Color]:
    """Paul Tol's nine light fills for labelled cells and qualitative maps.

    These pale colors are intended behind dark text, not for thin lines
    on a white background.
    """
    return [
        Color(119, 170, 221),
        Color(238, 136, 102),
        Color(238, 221, 136),
        Color(255, 170, 187),
        Color(153, 221, 255),
        Color(68, 187, 153),
        Color(187, 204, 51),
        Color(170, 170, 0),
        Color(221, 221, 221),
    ]


def tab10_legacy() -> List[Color]:
    """The eight tab10 colors used by dataviz before the accessible default."""
    return [
        Color(31, 119, 180),
        Color(255, 127, 14),
        Color(44, 160, 44),
        Color(214, 39, 40),
        Color(148, 103, 189),
        Color(140, 86, 75),
        Color(227, 119, 194),
        Color(127, 127, 127),
    ]
