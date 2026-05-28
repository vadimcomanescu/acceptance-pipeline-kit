import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["acceptance/generated/**/*.test.ts"],
    setupFiles: ["./handlers/calculator-handlers.ts"],
  },
});
