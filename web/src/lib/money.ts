/** Money is transported as a decimal string. Parse to cents (bigint) for maths. */
export const toCents = (php: string): bigint => {
  const m = /^-?\d+(\.\d{1,2})?$/.exec(php.trim());
  if (!m) throw new Error(`Not a money string: ${php}`);
  const [whole, frac = ""] = php.trim().split(".");
  return BigInt(whole + frac.padEnd(2, "0"));
};

export const fromCents = (c: bigint): string => {
  const sign = c < 0n ? "-" : "";
  const abs = c < 0n ? -c : c;
  const cents = (abs % 100n).toString().padStart(2, "0");
  return `${sign}${abs / 100n}.${cents}`;
};

export const formatPhp = (php: string) =>
  new Intl.NumberFormat("en-PH", { style: "currency", currency: "PHP" })
    .format(Number(php));   // display only — never feed this back into arithmetic
