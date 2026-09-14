struct Thing(Copyable, Movable):
    var callback: def(Int) thin -> Int

    def __init__(out self):
        self.callback = twice


def twice(x: Int) -> Int:
    return x * 2


def main():
    var a = Thing()
    var b = a.copy()
    var items = List[Thing]()
    items.append(b^)
    print(items[0].callback(7))
