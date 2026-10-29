import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.OPERATOR_KEY = '0x' + '11'.repeat(32);
const { closeLoop, decode, makeStamp } = await import('../lib/loop.ts');
const { seal, unseal } = await import('../lib/seal.ts');
const { hexIdOf } = await import('../lib/hexgrid.ts');

const WALLET = '0x00000000000000000000000000000000000000aa';
const CELL = 88n;

/** A ring of radius [n] around (q0, r0), walked one hex every [step] s. */
function ring(n: number, t0: number, step: number, wallet = WALLET) {
  const dirs = [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]];
  let q = 10 - n, r = 20 + n; // start at the south-west corner
  const stamps = [];
  let t = t0;
  stamps.push(makeStamp(wallet, hexIdOf(CELL, BigInt(q), BigInt(r)), t));
  for (const [dq, dr] of dirs) {
    for (let i = 0; i < n; i++) {
      q += dq; r += dr; t += step;
      stamps.push(makeStamp(wallet, hexIdOf(CELL, BigInt(q), BigInt(r)), t));
    }
  }
  return stamps;
}

test('a ring of radius 2 encloses the 7 hexes inside it', () => {
  const s = ring(2, 1000, 60);
  const loop = closeLoop(WALLET, s, 1000 + 60 * 12 + 5);
  assert.equal(loop.trail.length, 12);
  assert.equal(loop.inside.length, 7);
  const centre = hexIdOf(CELL, 10n, 20n);
  assert.ok(loop.inside.includes(centre));
  for (const id of loop.inside) {
    const { q, r } = decode(id);
    assert.ok((Math.abs(q - 10) + Math.abs(r - 20) + Math.abs(q + r - 30)) / 2 <= 1);
  }
});

test('a one-hex gap is filled in', () => {
  const s = ring(2, 1000, 60).filter((_, i) => i !== 3);
  const loop = closeLoop(WALLET, s, 1000 + 60 * 12 + 5);
  assert.equal(loop.trail.length, 12);
  assert.equal(loop.inside.length, 7);
});

test('driving, open loops, stale walks and borrowed stamps are refused', () => {
  assert.throws(() => closeLoop(WALLET, ring(2, 1000, 5), 1100), /Too fast/);
  assert.throws(() => closeLoop(WALLET, ring(2, 1000, 60).slice(0, -1), 1800), /starting hex/);
  assert.throws(() => closeLoop(WALLET, ring(2, 1000, 60), 1000 + 60 * 12 + 3600), /stale/);
  const theirs = ring(2, 1000, 60, '0x00000000000000000000000000000000000000bb');
  assert.throws(() => closeLoop(WALLET, theirs, 1000 + 60 * 12 + 5), /invalid/);
  const tampered = ring(2, 1000, 60);
  tampered[4] = { ...tampered[4], hexId: hexIdOf(CELL, 0n, 0n).toString() };
  assert.throws(() => closeLoop(WALLET, tampered, 1000 + 60 * 12 + 5), /invalid/);
});

test('a ring of radius 1 has an inside of exactly one hex', () => {
  const loop = closeLoop(WALLET, ring(1, 1000, 60), 1000 + 60 * 6 + 5);
  assert.equal(loop.trail.length, 6);
  assert.deepEqual(loop.inside, [hexIdOf(CELL, 10n, 20n)]);
});

test('sealed spots round-trip and reject tampering', () => {
  const blob = seal(22544800, 88342600);
  assert.equal(blob.length, 36);
  assert.deepEqual(unseal(blob), { lat: 22.5448, lng: 88.3426 });
  const bad = new Uint8Array(blob);
  bad[15] ^= 1;
  assert.throws(() => unseal(bad));
  assert.notDeepEqual(seal(22544800, 88342600), blob); // fresh IV each time
});
