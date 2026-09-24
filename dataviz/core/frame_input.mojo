"""Reading a `dataframe_mojo` column into the `List[Float64]`/
`List[String]` the rest of this package draws from (#364).

A dataframe column is a payload buffer plus an Arrow-style validity
bitmap, so two things have to come out of it: the values, and which of
them are there at all. Both come out, and what happens to a gap follows
`Theme.missing` (#367):

- A **value** column's invalid slots become `NaN`, the marker every
  column carries inside a `Plot`. The marks draw around it -- a line
  breaks, a point is not drawn.
- A **category** column's invalid slots become
  `Theme.missing_category_label`, because "not recorded" is a label a
  reader can use, and dropping those rows would throw away
  observations whose value is perfectly good.
- Under `Missing.RAISE` both are refused at the boundary, naming the
  column and the first row.

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

from std.utils.numerics import isnan, nan

from dataframe import DataFrame
from dataframe.dtype import DataType
from dataframe.series import Series
from morrow import Morrow

from dataviz.core.missing import Missing


def _frame_morrow(
    df: DataFrame, name: String, caller: String
) raises -> List[Morrow]:
    """Read a date or datetime column as UTC instants for a time axis."""
    var series = _frame_column(df, name, caller)
    var dtype = series.dtype()
    if not dtype.is_date() and not dtype.is_datetime():
        raise Error(
            caller
            + ': column "'
            + name
            + '" is '
            + dtype.name()
            + ", not a date or datetime column"
        )
    if series.null_count() > 0:
        for i in range(len(series)):
            if series.get(i).is_null():
                raise Error(
                    caller
                    + ': time column "'
                    + name
                    + '" has a missing value at row '
                    + String(i)
                )
    var column = series.numeric[DType.int64]()
    var values = column.unsafe_values()
    var out = List[Morrow](capacity=len(series))
    for i in range(len(series)):
        var raw = values[unsafe_offset=i]
        var seconds = Float64(raw) * 86400.0
        if dtype.is_datetime():
            var rate = dtype.per_second()
            seconds = Float64(raw // rate) + Float64(raw % rate) / Float64(rate)
        out.append(Morrow.utcfromtimestamp(seconds))
    _ = series.null_count()
    return out^


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


def _reject_nulls(
    series: Series, name: String, caller: String, missing: Missing
) raises:
    """Refuse a column with missing values under `Missing.RAISE`, naming
    the first row that is missing one.

    Under `Missing.DRAW` this returns and the caller carries the gap
    through -- as `NaN` for a value column, as
    `Theme.missing_category_label` for a category column.

    Args:
        series: The column to check.
        name: Its name, for the message.
        caller: The public function to name in an error.
        missing: The policy in force.

    Raises:
        Error: The policy is `Missing.RAISE` and the column has at least
            one missing value.
    """
    if missing != Missing.RAISE or series.null_count() == 0:
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
        + ". Theme(missing=Missing.DRAW), the default, draws around"
        " them instead; DataFrame.drop_nulls() and fill_null() are the"
        " other way"
    )


def _frame_floats(
    df: DataFrame,
    name: String,
    caller: String,
    missing: Missing = Missing.DRAW,
) raises -> List[Float64]:
    """A numeric column as `List[Float64]`.

    Any numeric dtype is accepted and cast, since every axis in this
    package is `Float64` anyway; a string or boolean column raises
    rather than being coerced into numbers it does not have.

    Args:
        df: The frame to read.
        name: The column's name.
        caller: The public function to name in an error.
        missing: The policy in force (`Theme.missing`).

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
    _reject_nulls(series, name, caller, missing)
    # `numeric` needs the exact dtype, and every axis here is Float64,
    # so the column is cast first. The cast is explicit on purpose:
    # dataframe_mojo does not promote on read, and a Float64 column's
    # cast is a window onto the same buffers rather than a conversion.
    var typed = series.cast(DataType.FLOAT64)
    var column = typed.numeric[DType.float64]()
    var values = column.unsafe_values()
    # An invalid slot holds whatever the buffer holds, as in Arrow, so
    # the validity bit decides -- never the payload.
    var holes = column.null_count() > 0
    var out = List[Float64](capacity=len(typed))
    for i in range(len(typed)):
        if holes and not column.is_valid(i):
            out.append(nan[DType.float64]())
        else:
            out.append(values[unsafe_offset=i])
    # `typed` owns the buffer `values` points into, so it has to outlive
    # the loop above; this keeps it alive past the last read.
    _ = typed.null_count()
    return out^


def _frame_strings(
    df: DataFrame,
    name: String,
    caller: String,
    missing: Missing = Missing.DRAW,
    label: String = "(missing)",
) raises -> List[String]:
    """A string column as `List[String]`, for a categorical channel.

    Args:
        df: The frame to read.
        name: The column's name.
        caller: The public function to name in an error.
        missing: The policy in force (`Theme.missing`).
        label: What an absent level is called
            (`Theme.missing_category_label`).

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
    _reject_nulls(series, name, caller, missing)
    # `string()` hands over the shared `StringColumn`, whose `to_list`
    # walks the `large_utf8` bytes and offsets directly -- no `AnyValue`
    # per row, the same shape as the numeric path above.
    var column = series.string()
    var out = column.to_list()
    if column.null_count() > 0:
        # A missing category is a label, not a hole: the rows stay, under
        # a name of their own (#367). `to_list` reads a null as "", which
        # is a real category a frame can also hold, so the validity bit
        # decides, not the value.
        for i in range(len(out)):
            if not column.is_valid(i):
                out[i] = label
    return out^


def _frame_bools(
    df: DataFrame,
    name: String,
    caller: String,
    missing: Missing = Missing.DRAW,
) raises -> List[Bool]:
    """A boolean column as `List[Bool]`, for the flag channels
    (`waterfall()`'s `is_total`).

    Args:
        df: The frame to read.
        name: The column's name.
        caller: The public function to name in an error.
        missing: The policy in force (`Theme.missing`).

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
    # A flag is neither a measurement nor a label: there is no third
    # state for it to take, so a missing one is refused under either
    # policy.
    _reject_nulls(series, name, caller, Missing.RAISE)
    var out = List[Bool](capacity=len(series))
    for i in range(len(series)):
        out.append(series.get(i).bool())
    return out^


def _frame_groups(
    df: DataFrame,
    category: String,
    value: String,
    caller: String,
    missing: Missing = Missing.DRAW,
    label: String = "(missing)",
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
        missing: The policy in force (`Theme.missing`).
        label: What an absent category is called
            (`Theme.missing_category_label`).

    Returns:
        The categories in first-appearance order, and one list of
        values per category, in the same order.

    Raises:
        Error: A named column is missing, has the wrong dtype for its
            channel, or has missing values.
    """
    var keys = _frame_strings(df, category, caller, missing, label)
    var values = _frame_floats(df, value, caller, missing)
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
    missing: Missing = Missing.DRAW,
    label: String = "(missing)",
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
        missing: The policy in force (`Theme.missing`).
        label: What an absent category is called
            (`Theme.missing_category_label`).

    Returns:
        The categories, the series names, and one row of values per
        series.

    Raises:
        Error: A named column is missing, has the wrong dtype, has
            missing values, or the pairs are not exactly one per cell.
    """
    var cats = _frame_strings(df, category, caller, missing, label)
    var names = _frame_strings(df, series, caller, missing, label)
    var numbers = _frame_floats(df, value, caller, missing)
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


def _frame_grid(
    df: DataFrame,
    row: String,
    column: String,
    value: String,
    caller: String,
    missing: Missing = Missing.DRAW,
) raises -> Tuple[List[Float64], List[Float64], List[List[Float64]]]:
    """A long-form frame as the `(y, x, z)` grid the field marks take:
    `z[i][j]` is the value at row key `y[i]` and column key `x[j]`.

    All three columns are numeric, because a field's axes are
    coordinates rather than labels -- these marks interpolate between
    them. Both key orders are ascending, which is what the marks'
    own `x`/`y` arguments require.

    A cell with no row is **missing**, not zero: it comes out as `NaN`,
    which the marks leave blank and the color limits skip (#367). That
    is what makes a pivot honest -- a rectangular grid out of a table
    that was never rectangular.

    Args:
        df: The frame to read.
        row: The numeric column giving each cell's row coordinate.
        column: The numeric column giving each cell's column coordinate.
        value: The numeric column holding each cell.
        caller: The public function to name in an error.
        missing: The policy in force (`Theme.missing`).

    Returns:
        The row keys ascending, the column keys ascending, and the grid.

    Raises:
        Error: A named column is missing, is not numeric, the columns
            differ in length, or a (row, column) pair repeats.
    """
    var rows = _frame_floats(df, row, caller, missing)
    var cols = _frame_floats(df, column, caller, missing)
    var values = _frame_floats(df, value, caller, missing)
    if len(rows) != len(cols) or len(rows) != len(values):
        raise Error(
            caller
            + ": the three columns have different lengths, "
            + String(len(rows))
            + ", "
            + String(len(cols))
            + " and "
            + String(len(values))
        )

    var y = _sorted_unique(rows)
    var x = _sorted_unique(cols)
    var z = List[List[Float64]]()
    var filled = List[List[Bool]]()
    for _ in range(len(y)):
        var line = List[Float64]()
        var seen = List[Bool]()
        for _ in range(len(x)):
            line.append(nan[DType.float64]())
            seen.append(False)
        z.append(line^)
        filled.append(seen^)

    for i in range(len(values)):
        # A row whose own coordinates are missing has no cell to land
        # in, so it takes no part.
        if isnan(rows[i]) or isnan(cols[i]):
            continue
        var ri = _index_of(y, rows[i])
        var ci = _index_of(x, cols[i])
        if filled[ri][ci]:
            raise Error(
                caller
                + ": more than one row at ("
                + String(rows[i])
                + ", "
                + String(cols[i])
                + "). A grid cell holds one value; aggregate first, with"
                " DataFrame.group_by(...).agg(...)"
            )
        z[ri][ci] = values[i]
        filled[ri][ci] = True
    return (y^, x^, z^)


def _sorted_unique(values: List[Float64]) -> List[Float64]:
    """The distinct present values, ascending: a grid axis's keys."""
    var out = List[Float64]()
    for v in values:
        if isnan(v):
            continue
        var seen = False
        for u in out:
            if u == v:
                seen = True
        if not seen:
            out.append(v)
    for i in range(1, len(out)):
        var k = i
        while k > 0 and out[k] < out[k - 1]:
            var t = out[k]
            out[k] = out[k - 1]
            out[k - 1] = t
            k -= 1
    return out^


def _index_of(keys: List[Float64], key: Float64) -> Int:
    """Where `key` sits in `keys`, which holds it by construction."""
    for i in range(len(keys)):
        if keys[i] == key:
            return i
    return 0


def _is_string_column(
    df: DataFrame, name: String, caller: String = "Plot.encode_frame()"
) raises -> Bool:
    """Whether `name` is a string column, which is what decides between
    a categorical and a continuous x channel.

    Args:
        df: The frame to read.
        name: The column's name.
        caller: Public operation named in a missing-column error.

    Returns:
        True for a string column.

    Raises:
        Error: No column of that name.
    """
    return _frame_column(df, name, caller).dtype() == DataType.STRING
