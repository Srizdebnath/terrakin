import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { hexIdAtE6, hexIdOf, zoneOf } from '../lib/hexgrid.ts';

const vectors: { lat: number; lng: number; hex: string }[] = JSON.parse(
  readFileSync(new URL('./hexgrid.json', import.meta.url), 'utf8'),
);

test('TypeScript hex ids match the Dart grid exactly', () => {
  assert.ok(vectors.length > 500);
  for (const v of vectors) {
    assert.equal(hexIdAtE6(v.lat, v.lng).toString(), v.hex, `${v.lat},${v.lng}`);
  }
});

test('packing matches the app', () => {
  assert.equal(hexIdOf(0n, 0n, 0n), 0x8000800000800000n);
  assert.equal(zoneOf(0, 0), 0x8000000080000000n);
  assert.equal(zoneOf(-5, -7), ((2n ** 31n - 5n) << 32n) | (2n ** 31n - 7n));
});
