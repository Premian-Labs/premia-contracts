export function isEqual(nb: number, other: number, precision?: number) {
  return Math.abs(nb - other) <= (precision ?? 0);
}
