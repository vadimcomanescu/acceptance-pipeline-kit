import { defaultRegistry } from "@aps-kit/typescript";
import { strict as assert } from "node:assert";

class Calculator {
  value = 0;
  add(a: number, b: number) {
    this.value = a + b;
  }
  subtract(a: number, b: number) {
    this.value = a - b;
  }
}

defaultRegistry.step("a fresh calculator", (world) => {
  world.calc = new Calculator();
});

defaultRegistry.step("I add <a> and <b>", (world, ex) => {
  (world.calc as Calculator).add(parseInt(ex.a, 10), parseInt(ex.b, 10));
});

defaultRegistry.step("I subtract <b> from <a>", (world, ex) => {
  (world.calc as Calculator).subtract(parseInt(ex.a, 10), parseInt(ex.b, 10));
});

defaultRegistry.step("the result is <sum>", (world, ex) => {
  assert.equal((world.calc as Calculator).value, parseInt(ex.sum, 10));
});

defaultRegistry.step("the result is <diff>", (world, ex) => {
  assert.equal((world.calc as Calculator).value, parseInt(ex.diff, 10));
});
