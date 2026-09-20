"""Reading a `dataframe_mojo` column into the `List[Float64]`/
`List[String]` the rest of this package draws from (#364).

A dataframe column is a payload buffer plus an Arrow-style validity
bitmap, so two things have to come out of it: the values, and which of
them are there at all. These helpers read both and refuse a column that
carries a missing value, naming it, because what a mark *draws* for a
gap -- a break in a line, a skipped point, a value left out of an
estimate -- is #367 and is not decided yet. Refusing is the honest
placeholder: it cannot silently drop a row or plot a zero where the
data says nothing.

Values are read straight out of Arrow's buffers -- `Column.
unsafe_values()` for the payload, `is_valid` for the bit -- rather than
through `Series.get`, which boxes every element into an `AnyValue`
carrying a `String` field a numeric column never fills and rescans the
dtype list per call. Upstream measured that difference at 1,000,000
rows: about 3,500 us through `get` against about 700 us reading the
buffers (dataframe_mojo#91, #99). `Column.value(i)` is slower still and
is not used here. A string column reads the same way, through
`Series.string()` and `StringColumn.to_list()`, which walks the
`large_utf8` bytes and offsets.

One copy remains, into the `List[Float64]` a `Plot` owns, because a
plot outlives the frame it was built from. The `Series` is kept alive
in each function for as long as its pointer is read, which is what the
buffer accessors require.
"""

from dataframe import DataFrame
from dataframe.dtype import DataType
from dataframe.series import Series


def _frame_column(df: DataFrame, name: String, caller: String) raises -> Series:
    """One named column, with a message that lists what is there when it
    is not.

    Args:
        df: The frame to read.
        name: The column's name.
        caller: The public function to name in an error.

    Returns:
        The column.

    Raises:
        Error: No column of that name.
    """
    try:
        return df.column(name)
    except:
        var names = String("")
        for i in range(len(df.columns())):
            if i > 0:
                names += ", "
            names += df.columns()[i]
        raise Error(
            caller + ': no column named "' + name + '". The frame has: ' + names
        )


def _reject_nulls(series: Series, name: String, caller: String) raises:
    """Refuse a column with missing values, naming the first row that is
    missing one.

    What each mark draws for a gap is #367. Until that is decided, a
    column with holes cannot be plotted without inventing an answer
    here, so this raises instead.

    Args:
        series: The column to check.
        name: Its name, for the message.
        caller: The public function to name in an error.

    Raises:
        Error: The column has at least one missing value.
    """
    if series.null_count() == 0:
        return
    var first = 0
    for i in range(len(series)):
        if series.get(i).is_null():
            first = i
            break
    raise Error(
        caller
        + ': column "'
        + name
        + '" has '
        + String(series.null_count())
        + " missing value(s), the first at row "
        + String(first)
        + ". What a mark draws for a gap is not decided yet"
        " (dataviz_mojo#367); drop or fill them first, with"
        " DataFrame.drop_nulls() or DataFrame.fill_null()"
    )


def _frame_floats(
    df: DataFrame, name: String, caller: String
) raises -> List[Float64]:
    """A numeric column as `List[Float64]`.

    Any numeric dtype is accepted and cast, since every axis in this
    package is `Float64` anyway; a string or boolean column raises
    rather than being coerced into numbers it does not have.

    Args:
        df: The frame to read.
        name: The column's name.
        caller: The public function to name in an error.

    Returns:
        The column's values, in row order.

    Raises:
        Error: No such column, it is not numeric, or it has missing
            values.
    """
    var series = _frame_column(df, name, caller)
    if not series.dtype().is_numeric():
        raise Error(
            caller
            + ': column "'
            + name
            + '" is '
            + series.dtype().name()
            + ", which is not a numeric column. A continuous channel"
            " needs numbers"
        )
    _reject_nulls(series, name, caller)
    # `numeric` needs the exact dtype, and every axis here is Float64,
    # so the column is cast first. The cast is explicit on purpose:
    # dataframe_mojo does not promote on read, and a Float64 column's
    # cast is a window onto the same buffers rather than a conversion.
    var typed = series.cast(DataType.FLOAT64)
    var column = typed.numeric[DType.float64]()
    var values = column.unsafe_values()
    var out = List[Float64](capacity=len(typed))
    for i in range(len(typed)):
        out.append(values[i])
    # `typed` owns the buffer `values` points into, so it has to outlive
    # the loop above; this keeps it alive past the last read.
    _ = typed.null_count()
    return out^


def _frame_strings(
    df: DataFrame, name: String, caller: String
) raises -> List[String]:
    """A string column as `List[String]`, for a categorical channel.

    Args:
        df: The frame to read.
        name: The column's name.
        caller: The public function to name in an error.

    Returns:
        The column's values, in row order.

    Raises:
        Error: No such column, it is not a string column, or it has
            missing values.
    """
    var series = _frame_column(df, name, caller)
    if series.dtype() != DataType.STRING:
        raise Error(
            caller
            + ': column "'
            + name
            + '" is '
            + series.dtype().name()
            + ", not a string column. A categorical channel needs"
            " strings; cast it first if the categories are numbers"
        )
    _reject_nulls(series, name, caller)
    # `string()` hands over the shared `StringColumn`, whose `to_list`
    # walks the `large_utf8` bytes and offsets directly -- no `AnyValue`
    # per row, the same shape as the numeric path above.
    return series.string().to_list()


def _frame_bools(
    df: DataFrame, name: String, caller: String
) raises -> List[Bool]:
    """A boolean column as `List[Bool]`, for the flag channels
    (`waterfall()`'s `is_total`).

    Args:
        df: The frame to read.
        name: The column's name.
        caller: The public function to name in an error.

    Returns:
        The column's values, in row order.

    Raises:
        Error: No such column, it is not boolean, or it has missing
            values.
    """
    var series = _frame_column(df, name, caller)
    if series.dtype() != DataType.BOOL:
        raise Error(
            caller
            + ': column "'
            + name
            + '" is '
            + series.dtype().name()
            + ", not a boolean column"
        )
    _reject_nulls(series, name, caller)
    var out = List[Bool](capacity=len(series))
    for i in range(len(series)):
        out.append(series.get(i).bool())
    return out^


def _frame_groups(
    df: DataFrame, category: String, value: String, caller: String
) raises -> Tuple[List[String], List[List[Float64]]]:
    """A long-form frame as the `(categories, values)` pair the
    distribution and multi-series marks take.

    A dataframe holds these long -- one row per observation, with a
    category beside it -- while the marks want one list of values per
    category. This buckets the value column by the category column,
    keeping each category's first appearance as its order, which is the
    order `encode_categorical()` already gives a category list.

    Args:
        df: The frame to read.
        category: The string column naming each observation's group.
        value: The numeric column holding the observations.
        caller: The public function to name in an error.

    Returns:
        The categories in first-appearance order, and one list of
        values per category, in the same order.

    Raises:
        Error: A named column is missing, has the wrong dtype for its
            channel, or has missing values.
    """
    var keys = _frame_strings(df, category, caller)
    var values = _frame_floats(df, value, caller)
    if len(keys) != len(values):
        raise Error(
            caller
            + ': columns "'
            + category
            + '" and "'
            + value
            + '" have different lengths, '
            + String(len(keys))
            + " and "
            + String(len(values))
        )
    var order = List[String]()
    var grouped = List[List[Float64]]()
    for i in range(len(keys)):
        var at = -1
        for k in range(len(order)):
            if order[k] == keys[i]:
                at = k
                break
        if at < 0:
            order.append(keys[i])
            grouped.append(List[Float64]())
            at = len(order) - 1
        grouped[at].append(values[i])
    return (order^, grouped^)


def _frame_series(
    df: DataFrame,
    category: String,
    series: String,
    value: String,
    caller: String,
) raises -> Tuple[List[String], List[String], List[List[Float64]]]:
    """A long-form frame as the `(categories, series_names, values)`
    triple the multi-series marks take, where `values[j]` is series
    `j`'s value for each category in turn.

    Both orders are first appearance, as `_frame_groups` does. Every
    (series, category) pair must appear exactly once: a missing pair
    would have to be invented as a zero, which is a claim about the
    data, and a repeated one is ambiguous. Both raise, naming the pair.

    Args:
        df: The frame to read.
        category: The string column naming each column of the grid.
        series: The string column naming each series.
        value: The numeric column holding each cell.
        caller: The public function to name in an error.

    Returns:
        The categories, the series names, and one row of values per
        series.

    Raises:
        Error: A named column is missing, has the wrong dtype, has
            missing values, or the pairs are not exactly one per cell.
    """
    var cats = _frame_strings(df, category, caller)
    var names = _frame_strings(df, series, caller)
    var numbers = _frame_floats(df, value, caller)
    if len(cats) != len(names) or len(cats) != len(numbers):
        raise Error(
            caller
            + ": the three columns have different lengths, "
            + String(len(cats))
            + ", "
            + String(len(names))
            + " and "
            + String(len(numbers))
        )

    var cat_order = List[String]()
    var series_order = List[String]()
    for i in range(len(cats)):
        var seen = False
        for c in cat_order:
            if c == cats[i]:
                seen = True
        if not seen:
            cat_order.append(cats[i])
        seen = False
        for n in series_order:
            if n == names[i]:
                seen = True
        if not seen:
            series_order.append(names[i])

    var values = List[List[Float64]]()
    var filled = List[List[Bool]]()
    for _ in range(len(series_order)):
        var row = List[Float64]()
        var seen_row = List[Bool]()
        for _ in range(len(cat_order)):
            row.append(0.0)
            seen_row.append(False)
        values.append(row^)
        filled.append(seen_row^)

    for i in range(len(cats)):
        var ci = 0
        for k in range(len(cat_order)):
            if cat_order[k] == cats[i]:
                ci = k
                break
        var si = 0
        for k in range(len(series_order)):
            if series_order[k] == names[i]:
                si = k
                break
        if filled[si][ci]:
            raise Error(
                caller
                + ': more than one row for series "'
                + names[i]
                + '" in category "'
                + cats[i]
                + '". Aggregate first, with DataFrame.group_by(...).agg(...)'
            )
        values[si][ci] = numbers[i]
        filled[si][ci] = True

    for si in range(len(series_order)):
        for ci in range(len(cat_order)):
            if not filled[si][ci]:
                raise Error(
                    caller
                    + ': no row for series "'
                    + series_order[si]
                    + '" in category "'
                    + cat_order[ci]
                    + '". Every series needs a value in every category;'
                    " fill the gaps first, since a missing cell is not"
                    " the same claim as a zero"
                )
    return (cat_order^, series_order^, values^)


def _is_string_column(df: DataFrame, name: String) raises -> Bool:
    """Whether `name` is a string column, which is what decides between
    a categorical and a continuous x channel.

    Args:
        df: The frame to read.
        name: The column's name.

    Returns:
        True for a string column.

    Raises:
        Error: No column of that name.
    """
    return _frame_column(df, name, "Plot.encode_frame()").dtype() == (
        DataType.STRING
    )
