import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { AFFINITIES, spawnFromId } from '../lib/spawn.ts';

const vectors = JSON.parse(readFileSync(new URL('./vectors.json', import.meta.url), 'utf8'));

test('TypeScript spawns match the Dart engine exactly', () => {
  assert.ok(vectors.length > 100);
  for (const v of vectors) {
    const boosted = v.boosted.map((a: string) => AFFINITIES.indexOf(a as never));
    const s = spawnFromId(v.id, boosted);
    assert.ok(s, `could not re-derive ${v.id}`);
    assert.equal(s.kind, v.kind, v.id);
    assert.equal(s.species, v.species, `${v.id} species`);
    assert.equal(s.grade, v.grade, `${v.id} grade`);
    assert.deepEqual(s.vigor, v.vigor, `${v.id} vigor`);
    assert.equal(s.trait, v.trait, `${v.id} trait`);
    assert.ok(Math.abs(s.lat - v.lat) < 1e-9, `${v.id} lat ${s.lat} vs ${v.lat}`);
    assert.ok(Math.abs(s.lng - v.lng) < 1e-9, `${v.id} lng ${s.lng} vs ${v.lng}`);
    assert.equal(s.expires, v.expires, `${v.id} expires`);
  }
});

test('garbage ids are rejected', () => {
  for (const id of ['', 'x', '1:2:3', '1:2:3:9:9', 'w1:2:3:hail', 'L1:2']) {
    assert.equal(spawnFromId(id), null, id);
  }
});
