import { createHmac, timingSafeEqual } from 'node:crypto';
import { derivedKey } from './secrets.js';

// Loop Capture. While a player walks in loop mode the app asks for a stamp in
// every hex it enters; each stamp is an HMAC over (wallet, hex, time), so it
// can't be forged or lent to another wallet. Closing the loop sends the stamps
// back: we check the walk was continuous and humanly paced, then flood-fill
// the hex grid to find what the loop encloses.

export interface Stamp {
  hexId: string;
  t: number; // unix seconds
  mac: string;
}

export const MAX_LOOP = 160; // TerrakinTerritory.MAX_LOOP
const MIN_TRAIL = 6;
const MAX_SPAN_S = 2 * 60 * 60;
const MIN_STEP_S = 15; // per hex (~150 m): about 36 km/h, a sprint is fine
const FRESH_S = 10 * 60;

const mac = (wallet: string, hexId: string, t: number) =>
  createHmac('sha256', derivedKey('loop-stamps')).update(`${wallet.toLowerCase()}|${hexId}|${t}`).digest('base64url').slice(0, 22);

export function makeStamp(wallet: string, hexId: bigint, t: number): Stamp {
  return { hexId: hexId.toString(), t, mac: mac(wallet, hexId.toString(), t) };
}

function stampOk(wallet: string, s: Stamp): boolean {
  if (typeof s?.hexId !== 'string' || !/^\d{1,20}$/.test(s.hexId) || !Number.isInteger(s.t) || typeof s.mac !== 'string') return false;
  const enc = new TextEncoder();
  const want = enc.encode(mac(wallet, s.hexId, s.t));
  const got = enc.encode(s.mac);
  return want.length === got.length && timingSafeEqual(want, got);
}

/** Hex id layout from hexgrid.ts: (strip + 2^15) << 48 | (q + 2^23) << 24 | (r + 2^23). */
export function decode(id: bigint): { cell: bigint; q: number; r: number } {
  return {
    cell: (id >> 48n) - 0x8000n,
    q: Number((id >> 24n) & 0xffffffn) - 0x800000,
    r: Number(id & 0xffffffn) - 0x800000,
  };
}

const encode = (cell: bigint, q: number, r: number) =>
  ((cell + 0x8000n) << 48n) | ((BigInt(q) + 0x800000n) << 24n) | (BigInt(r) + 0x800000n);

const dist = (a: { q: number; r: number }, b: { q: number; r: number }) =>
  (Math.abs(a.q - b.q) + Math.abs(a.r - b.r) + Math.abs(a.q + a.r - b.q - b.r)) / 2;

const DIRS = [
  [1, 0],
  [1, -1],
  [0, -1],
  [-1, 0],
  [-1, 1],
  [0, 1],
];

export class LoopError extends Error {}

export interface Loop {
  startedAt: number;
  trail: bigint[];
  inside: bigint[];
}

/** Validates a walk and returns the loop's trail and enclosed hexes. */
export function closeLoop(wallet: string, stamps: Stamp[], nowS: number): Loop {
  if (!Array.isArray(stamps) || stamps.length < MIN_TRAIL + 1 || stamps.length > 400) {
    throw new LoopError('Walk at least 6 hexes and come back to where you started');
  }
  for (const s of stamps) if (!stampOk(wallet, s)) throw new LoopError('A walk stamp is invalid');
  const first = stamps[0];
  const last = stamps[stamps.length - 1];
  if (last.t - first.t > MAX_SPAN_S) throw new LoopError('Loops must close within 2 hours');
  if (nowS - last.t > FRESH_S) throw new LoopError('This walk is stale; start a new loop');
  if (first.hexId !== last.hexId) throw new LoopError('Come back to your starting hex to close the loop');

  const cells = stamps.map((s) => decode(BigInt(s.hexId)));
  const cell = cells[0].cell;
  if (cells.some((c) => c.cell !== cell)) throw new LoopError('Loops can’t cross a 1° longitude line');

  // The path, with a one-hex gap filled in (GPS can skip a corner).
  const path: { q: number; r: number }[] = [cells[0]];
  for (let i = 1; i < cells.length; i++) {
    const a = path[path.length - 1];
    const b = cells[i];
    const d = dist(a, b);
    if (stamps[i].t < stamps[i - 1].t) throw new LoopError('Walk stamps are out of order');
    if (d === 0) continue;
    if (d > 2) throw new LoopError('Your walk has a gap; keep the app open while you walk');
    if (stamps[i].t - stamps[i - 1].t < d * MIN_STEP_S) throw new LoopError('Too fast: loops are walked, not driven');
    if (d === 2) {
      const mid = DIRS.map(([dq, dr]) => ({ q: a.q + dq, r: a.r + dr })).find((m) => dist(m, b) === 1)!;
      path.push(mid);
    }
    path.push(b);
  }

  const key = (q: number, r: number) => `${q},${r}`;
  const onTrail = new Set(path.map((p) => key(p.q, p.r)));
  if (onTrail.size < MIN_TRAIL) throw new LoopError('Walk at least 6 different hexes');

  let minQ = Infinity, maxQ = -Infinity, minR = Infinity, maxR = -Infinity;
  for (const p of path) {
    minQ = Math.min(minQ, p.q); maxQ = Math.max(maxQ, p.q);
    minR = Math.min(minR, p.r); maxR = Math.max(maxR, p.r);
  }
  minQ--; maxQ++; minR--; maxR++;
  if ((maxQ - minQ + 1) * (maxR - minR + 1) > 4000) throw new LoopError('That loop is too big');

  // Flood the box from a corner; whatever the water can't reach is enclosed.
  const outside = new Set<string>([key(minQ, minR)]);
  const queue: [number, number][] = [[minQ, minR]];
  while (queue.length) {
    const [q, r] = queue.pop()!;
    for (const [dq, dr] of DIRS) {
      const nq = q + dq, nr = r + dr;
      const k = key(nq, nr);
      if (nq < minQ || nq > maxQ || nr < minR || nr > maxR || outside.has(k) || onTrail.has(k)) continue;
      outside.add(k);
      queue.push([nq, nr]);
    }
  }
  const inside: bigint[] = [];
  for (let q = minQ; q <= maxQ; q++) {
    for (let r = minR; r <= maxR; r++) {
      const k = key(q, r);
      if (!outside.has(k) && !onTrail.has(k)) inside.push(encode(cell, q, r));
    }
  }
  if (inside.length === 0) throw new LoopError('Your loop doesn’t enclose any hexes; walk a wider circle');

  const seen = new Set<string>();
  const trail: bigint[] = [];
  for (const p of path) {
    const k = key(p.q, p.r);
    if (seen.has(k)) continue;
    seen.add(k);
    trail.push(encode(cell, p.q, p.r));
  }
  if (trail.length + inside.length > MAX_LOOP) throw new LoopError(`Loops can take at most ${MAX_LOOP} hexes; walk a smaller one`);
  return { startedAt: first.t, trail, inside };
}
