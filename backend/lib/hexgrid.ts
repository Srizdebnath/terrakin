// Server-side mirror of app/lib/core/hexgrid.dart. Must stay bit-for-bit
// identical: the backend signs the hex id a player stands in, and the app
// computes the same id to draw and look up territory. BigInt keeps every
// division truncating toward zero exactly like Dart's ~/.
// test/hexgrid.test.ts checks it against vectors exported from Dart.

const SIZE = 780n;
const STRIP = 1_000_000n;
const FP = 1_000_000n;

const floorDiv = (a: bigint, b: bigint) => {
  const q = a / b;
  return a % b !== 0n && a < 0n ? q - 1n : q;
};
const roundFp = (v: bigint) => floorDiv(v + FP / 2n, FP);
const abs = (v: bigint) => (v < 0n ? -v : v);

export function cosE6(latE6: bigint): bigint {
  const lat = latE6 < -85_000_000n ? -85_000_000n : latE6 > 85_000_000n ? 85_000_000n : latE6;
  const rad = (lat * 17_453_293n) / 1_000_000_000n;
  const x2 = (rad * rad) / FP;
  let term = FP;
  let c = FP;
  for (let k = 1n; k <= 6n; k++) {
    term = -((term * x2) / FP / ((2n * k - 1n) * (2n * k)));
    c += term;
  }
  return c;
}

/** uint64 hex id: (strip + 2^15) << 48 | (q + 2^23) << 24 | (r + 2^23). */
export function hexIdOf(cell: bigint, q: bigint, r: bigint): bigint {
  return ((cell + 0x8000n) << 48n) | (((q + 0x800000n) & 0xffffffn) << 24n) | ((r + 0x800000n) & 0xffffffn);
}

/** Hex containing a point given in micro-degrees. */
export function hexIdAtE6(latE6: number | bigint, lngE6: number | bigint): bigint {
  const lat = BigInt(latE6);
  const lng = BigInt(lngE6);
  const cell = floorDiv(lng, STRIP);
  const x = ((lng - cell * STRIP) * cosE6(lat)) / FP;
  const y = lat;
  const qf = (577_350n * x - 333_333n * y) / SIZE;
  const rf = (666_667n * y) / SIZE;
  const sf = -qf - rf;
  let q = roundFp(qf);
  let r = roundFp(rf);
  const s = roundFp(sf);
  const dq = abs(q * FP - qf);
  const dr = abs(r * FP - rf);
  const ds = abs(s * FP - sf);
  if (dq > dr && dq > ds) q = -r - s;
  else if (dr > ds) r = -q - s;
  return hexIdOf(cell, q, r);
}

export const hexIdAt = (lat: number, lng: number) => hexIdAtE6(Math.round(lat * 1e6), Math.round(lng * 1e6));

/** uint64 Landmark zone id: (row + 2^31) << 32 | (col + 2^31). */
export function zoneOf(row: number, col: number): bigint {
  return ((BigInt(row) + (1n << 31n)) << 32n) | ((BigInt(col) + (1n << 31n)) & 0xffffffffn);
}
