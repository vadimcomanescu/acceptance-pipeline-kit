from aps_kit.registry import default_registry as registry


class Calculator:
    def __init__(self) -> None:
        self.value = 0

    def add(self, a: int, b: int) -> None:
        self.value = a + b

    def subtract(self, a: int, b: int) -> None:
        self.value = a - b


@registry.step("a fresh calculator")
def _(world, _ex):
    world["calc"] = Calculator()


@registry.step("I add <a> and <b>")
def _(world, ex):
    world["calc"].add(int(ex["a"]), int(ex["b"]))


@registry.step("I subtract <b> from <a>")
def _(world, ex):
    world["calc"].subtract(int(ex["a"]), int(ex["b"]))


@registry.step("the result is <sum>")
def _(world, ex):
    assert world["calc"].value == int(ex["sum"]), (
        f"expected {ex['sum']}, got {world['calc'].value}"
    )


@registry.step("the result is <diff>")
def _(world, ex):
    assert world["calc"].value == int(ex["diff"]), (
        f"expected {ex['diff']}, got {world['calc'].value}"
    )
