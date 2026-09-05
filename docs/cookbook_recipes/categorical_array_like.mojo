"""Plot bar categories from your own custom container -- conform a
struct to `StringSequence` and pass it straight to `Plot.
encode_categorical()`'s `x`, the same way a `Float64Sequence` struct
plugs into `encode()`'s `x`/`y`.
"""
from dataviz.array_like import StringSequence
from dataviz.plot import Plot, save


struct UppercaseLabels(Copyable, Movable, StringSequence):
    """Stands in for a real-world array-like source (a dataframe
    column, a database result column) -- upper-cases each entry on the
    fly, without ever copying the underlying list into a new one
    itself.
    """

    var data: List[String]

    def __init__(out self, var data: List[String]):
        self.data = data^

    def __len__(self) -> Int:
        return len(self.data)

    def __getitem__(self, idx: Int) -> String:
        return self.data[idx].upper()


def main() raises:
    var raw: List[String] = ["mon", "tue", "wed", "thu", "fri"]
    var categories = UppercaseLabels(raw^)
    var revenue: List[Float64] = [12.0, 19.0, 8.0, 15.0, 22.0]

    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=categories, y=revenue)
        .labels(title="Revenue by Day", y_title="Revenue ($K)")
    )
    save(plot, "docs/src/examples/out_categorical_array_like.svg")
