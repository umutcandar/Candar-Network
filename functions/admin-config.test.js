"use strict";
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { normalizeMiningRate } = require("./admin-config");

test("admin rate rejects invalid and out-of-range input", () => {
  for (const input of [-1, 0, 0.8, 5.1, "NaN", "", null, undefined, {}, Infinity]) {
    assert.equal(normalizeMiningRate(input, null), null);
  }
});
test("admin rate accepts valid input with two decimal precision", () => {
  assert.equal(normalizeMiningRate("1.234", null), 1.23);
  assert.equal(normalizeMiningRate(2, null), 2);
  assert.equal(normalizeMiningRate(5, null), 5);
});
test("fallback is used only for absent or invalid config", () => {
  assert.equal(normalizeMiningRate(undefined, 1), 1);
  assert.equal(normalizeMiningRate(1.5, 1), 1.5);
});
