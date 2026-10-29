import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.OPERATOR_KEY = '0x' + '11'.repeat(32);
const { makeWalkStamp, measureWalk } = await import('../lib/walk.ts');

const WALLET = '0x00000000000000000000000000000000000000aa';
const LAT = 22.5448, LNG = 88.3426;
const NORTH = 1 / 111195; // degrees per metre

/** Stamps every [stepM] metres north, [stepS] seconds apart. */
function walkNorth(n: number, stepM: number, stepS: number, t0 = 1000, wallet = WALLET) {
  return Array.from({ length: n }, (_, i) => makeWalkStamp(wallet, LAT + i * stepM * NORTH, LNG, t0 + i * stepS));
}

test('1.15 km at walking pace pays two steps and keeps the remainder', () => {
  const s = walkNorth(12, 105, 70); // 1155 m
  const w = measureWalk(WALLET, s, 1000 + 11 * 70 + 5);
  assert.ok(w.metres >= 1000 && w.metres < 1100, String(w.metres));
  assert.equal(w.keepFrom, 10);
  assert.equal(w.to, s[10].t);
  assert.equal(w.from, s[0].t);
});

test('short walks, driving and stolen stamps earn nothing', () => {
  assert.throws(() => measureWalk(WALLET, walkNorth(5, 100, 70), 1300), /Walk 500 m/);
  assert.throws(() => measureWalk(WALLET, walkNorth(12, 100, 10), 1120), /Walk 500 m/); // 36 km/h
  const theirs = walkNorth(12, 100, 70, 1000, '0x00000000000000000000000000000000000000bb');
  assert.throws(() => measureWalk(WALLET, theirs, 1800), /invalid/);
  const forged = walkNorth(12, 100, 70);
  forged[3] = { ...forged[3], lat: forged[3].lat + 50 };
  assert.throws(() => measureWalk(WALLET, forged, 1800), /invalid/);
  assert.throws(() => measureWalk(WALLET, walkNorth(12, 100, 70), 1000 + 11 * 70 + 601), /stale/);
});
