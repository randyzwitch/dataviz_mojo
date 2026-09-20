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
