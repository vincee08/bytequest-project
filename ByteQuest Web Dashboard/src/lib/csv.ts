/**
 * Serializes one CSV cell and neutralizes values that spreadsheet programs may
 * otherwise interpret as formulas. Numeric values remain numeric.
 */
export function escapeCsvCell(value: unknown): string {
  const raw = value === null || value === undefined ? "" : String(value);
  const text =
    typeof value === "string" && /^[\u0000-\u0020]*[=+\-@]/.test(raw)
      ? `'${raw}`
      : raw;

  return /[",\r\n]/.test(text)
    ? `"${text.replaceAll('"', '""')}"`
    : text;
}
