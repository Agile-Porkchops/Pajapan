import { describe, expect, it } from "vitest";
import { fromCents, toCents } from "./money";

describe("toCents", () => {
  it("parses whole and fractional pesos", () => {
    expect(toCents("1234.50")).toBe(123450n);
    expect(toCents("0.05")).toBe(5n);
  });

  it("rejects more than two decimal places", () => {
    expect(() => toCents("12.345")).toThrow();
  });

  it("rejects non-numeric input", () => {
    expect(() => toCents("abc")).toThrow();
  });
});

describe("fromCents", () => {
  it("round-trips toCents, including negative amounts under one peso", () => {
    // A refund adjustment like -0.05 must not lose its sign — the whole-number
    // part is 0, which is where a naive (c / 100n) truncates the sign away.
    expect(fromCents(toCents("1234.50"))).toBe("1234.50");
    expect(fromCents(-5n)).toBe("-0.05");
  });
});
