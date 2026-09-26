"""How a categorical mark orders its categories, set via
`Chart.sort_categories()` (#843)."""

from dataviz.core.plot_fields import (
    _CategoricalData,
    _ContinuousData,
    _ErrorBarData,
)


struct CategoryOrder(Copyable, ImplicitlyCopyable, Movable):
    """The order a categorical mark draws its categories in, by value or
    by label. Input order, what a chart draws without asking, needs no
    constant: it is what not calling `sort_categories()` gives. An
    order named category by category is `sort_categories()`'s
    `List[String]` overload instead.

    Every sort is stable, so categories that tie keep their input order,
    and a category whose value is missing sorts last in either
    direction, since a missing value is neither large nor small.
    Horizontal marks draw their first category at the top, so
    `VALUE_DESCENDING` puts the largest bar at the top, the order a
    ranked list reads in.
    """

    var _value: Int

    comptime VALUE_ASCENDING = Self(0)
    """Smallest value first."""
    comptime VALUE_DESCENDING = Self(1)
    """Largest value first: the ranked bar chart."""
    comptime LABEL_ASCENDING = Self(2)
    """Alphabetical by category name, compared byte by byte."""
    comptime LABEL_DESCENDING = Self(3)
    """Reverse alphabetical by category name."""

    def __init__(out self, value: Int):
        """Prefer the comptime constants over constructing one directly.

        Args:
            value: 0 to 3, in the order the constants are declared.
        """
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def __ne__(self, other: Self) -> Bool:
        return self._value != other._value

    def name(self) -> String:
        """This order's constant name, for messages.

        Returns:
            The constant's name, or "CategoryOrder(<n>)" outside them.
        """
        if self._value == 0:
            return "VALUE_ASCENDING"
        if self._value == 1:
            return "VALUE_DESCENDING"
        if self._value == 2:
            return "LABEL_ASCENDING"
        if self._value == 3:
            return "LABEL_DESCENDING"
        return "CategoryOrder(" + String(self._value) + ")"


def _before(
    a: Int,
    b: Int,
    order: CategoryOrder,
    categories: List[String],
    values: List[Float64],
) -> Bool:
    """Whether index `a` sorts strictly before index `b` under `order`.
    Strict, so a stable merge keeps ties in input order."""
    if order == CategoryOrder.LABEL_ASCENDING:
        return categories[a] < categories[b]
    if order == CategoryOrder.LABEL_DESCENDING:
        return categories[b] < categories[a]
    var va = values[a]
    var vb = values[b]
    var a_missing = va != va
    var b_missing = vb != vb
    if a_missing or b_missing:
        return b_missing and not a_missing
    if order == CategoryOrder.VALUE_ASCENDING:
        return va < vb
    return vb < va


def _category_permutation(
    categories: List[String], values: List[Float64], order: CategoryOrder
) raises -> List[Int]:
    """The input indices in `order`: a stable merge sort, so the cost
    is `n log n` however many categories a chart has.

    Raises:
        Error: `order` is not one of the four constants.
    """
    if not (
        order == CategoryOrder.VALUE_ASCENDING
        or order == CategoryOrder.VALUE_DESCENDING
        or order == CategoryOrder.LABEL_ASCENDING
        or order == CategoryOrder.LABEL_DESCENDING
    ):
        raise Error("sort_categories(): unknown order " + order.name())
    var idx = List[Int](capacity=len(categories))
    for i in range(len(categories)):
        idx.append(i)
    var scratch = idx.copy()
    var width = 1
    var n = len(idx)
    while width < n:
        var lo = 0
        while lo < n:
            var mid = min(lo + width, n)
            var hi = min(lo + 2 * width, n)
            var i = lo
            var j = mid
            var k = lo
            while i < mid and j < hi:
                if _before(idx[j], idx[i], order, categories, values):
                    scratch[k] = idx[j]
                    j += 1
                else:
                    scratch[k] = idx[i]
                    i += 1
                k += 1
            while i < mid:
                scratch[k] = idx[i]
                i += 1
                k += 1
            while j < hi:
                scratch[k] = idx[j]
                j += 1
                k += 1
            lo = hi
        var swap = idx^
        idx = scratch^
        scratch = swap^
        width *= 2
    return idx^


def _named_permutation(
    categories: List[String], names: List[String]
) raises -> List[Int]:
    """The input indices in the order `names` gives them.

    `names` must name every category exactly once: a missing one would
    drop data from the chart, an unknown or repeated one is a typo, and
    both are refused with the name that caused it.

    Raises:
        Error: `names` misses, repeats or invents a category.
    """
    var seen = List[Bool](length=len(categories), fill=False)
    var out = List[Int](capacity=len(categories))
    for name in names:
        var found = -1
        for i in range(len(categories)):
            if categories[i] == name:
                found = i
                break
        if found < 0:
            raise Error(
                'sort_categories(): "'
                + name
                + "\" is not one of this chart's categories"
            )
        if seen[found]:
            raise Error(
                'sort_categories(): "' + name + '" is named more than once'
            )
        seen[found] = True
        out.append(found)
    for i in range(len(categories)):
        if not seen[i]:
            raise Error(
                'sort_categories(): the order does not name "'
                + categories[i]
                + '"; every category must appear exactly once'
            )
    return out^


def _permuted(values: List[Float64], perm: List[Int]) -> List[Float64]:
    """`values` reordered by `perm`, or empty when `values` is."""
    if len(values) == 0:
        return List[Float64]()
    var out = List[Float64](capacity=len(perm))
    for i in perm:
        out.append(values[i])
    return out^


def _apply_category_permutation(
    mut categorical: _CategoricalData,
    mut continuous: _ContinuousData,
    mut error_bars: _ErrorBarData,
    perm: List[Int],
):
    """Reorder every per-category column of a categorical mark by
    `perm`: the categories, their values and any error bars, so each
    stays attached to its own category."""
    var cats = List[String](capacity=len(perm))
    for i in perm:
        cats.append(categorical.x[i])
    categorical.x = cats^
    continuous.y = _permuted(continuous.y, perm)
    error_bars.symmetric = _permuted(error_bars.symmetric, perm)
    error_bars.lower = _permuted(error_bars.lower, perm)
    error_bars.upper = _permuted(error_bars.upper, perm)


def _require_categories(
    categorical: _CategoricalData, continuous: _ContinuousData
) raises:
    """`sort_categories()` reorders data the chart already holds, so it
    has to come after the call that gives the chart its categories, and
    one value per category is what keeps the permutation meaningful."""
    if len(categorical.x) == 0:
        raise Error(
            "sort_categories(): this chart has no categories yet; call it"
            " after encode_categorical() (or the one-call function that"
            " takes them)"
        )
    if len(continuous.y) != len(categorical.x):
        raise Error(
            "sort_categories(): x and y must have the same length (got "
            + String(len(categorical.x))
            + " and "
            + String(len(continuous.y))
            + ")"
        )


def _sort_categories(
    mut categorical: _CategoricalData,
    mut continuous: _ContinuousData,
    mut error_bars: _ErrorBarData,
    order: CategoryOrder,
) raises:
    """`sort_categories(order)`'s body for every categorical mark."""
    _require_categories(categorical, continuous)
    var perm = _category_permutation(categorical.x, continuous.y, order)
    _apply_category_permutation(categorical, continuous, error_bars, perm)


def _sort_categories_named(
    mut categorical: _CategoricalData,
    mut continuous: _ContinuousData,
    mut error_bars: _ErrorBarData,
    names: List[String],
) raises:
    """`sort_categories(names)`'s body for every categorical mark."""
    _require_categories(categorical, continuous)
    var perm = _named_permutation(categorical.x, names)
    _apply_category_permutation(categorical, continuous, error_bars, perm)
