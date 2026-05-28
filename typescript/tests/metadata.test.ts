import { describe, expect, test } from "vitest";

import { metadataFilename } from "../src/metadata.js";

describe("metadataFilename", () => {
  test("features subdir", () => {
    expect(metadataFilename("features/Hunt The Wumpus.feature")).toBe(
      "features-hunt-the-wumpus-feature.json",
    );
  });
  test("nested features", () => {
    expect(metadataFilename("features/orders/Cancel Order.feature")).toBe(
      "features-orders-cancel-order-feature.json",
    );
  });
  test("mixed case + punctuation", () => {
    expect(metadataFilename("Features/API v2/Happy Path.feature")).toBe(
      "features-api-v2-happy-path-feature.json",
    );
  });
});
