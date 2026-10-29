// Server-side mirror of app/lib/data/spawn_engine.dart and app/lib/core/rng.dart.
// Must stay bit-for-bit identical: the backend re-derives a spawn from its id
// before signing a bond voucher. test/spawn.test.ts checks it against vectors
// exported from the Dart engine.

export const SPECIES = ['mossling', 'ripplet', 'emberpup', 'glyphlet', 'shardlet', 'sparkit', 'pebblet'] as const;
// Species i has Affinity i (grove, tide, forge, rune, prism, volt, stone).
export const AFFINITIES = ['grove', 'tide', 'forge', 'rune', 'prism', 'volt', 'stone'] as const;
export const SKIES = ['clear', 'partlyCloudy', 'cloudy', 'fog', 'drizzle', 'rain', 'snow', 'storm'] as const;
export type Sky = (typeof SKIES)[number];

const GRADE_WEIGHTS = [62, 26, 9.5, 2.3, 0.2];
const TRAITS = 7;
const CELL_DEG = 0.0015;
const ZONE_DEG = 0.04;
const WINDOW_MS = 15 * 60 * 1000;
export const DAY_MS = 24 * 60 * 60 * 1000;

export function hash32(a: number, b: number, c: number, salt: number): number {
  let h = Math.imul(salt >>> 0, 0x9e3779b1) >>> 0;
  h = Math.imul((h ^ a) >>> 0, 0x85ebca6b) >>> 0;
  h = (h ^ (h >>> 13)) >>> 0;
  h = Math.imul((h ^ b) >>> 0, 0xc2b2ae35) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  h = Math.imul((h ^ c) >>> 0, 0x27d4eb2f) >>> 0;
  h = (h ^ (h >>> 15)) >>> 0;
  return h >>> 0;
}

export class Mulberry32 {
  private s: number;
  constructor(seed: number) {
    this.s = seed >>> 0;
  }
  nextUint32(): number {
    this.s = (this.s + 0x6d2b79f5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return (t ^ (t >>> 14)) >>> 0;
  }
  nextDouble(): number {
    return this.nextUint32() / 4294967296;
  }
  nextInt(max: number): number {
    return Math.floor(this.nextDouble() * max);
  }
}

export interface Genes {
  species: number;
  grade: number;
  vigor: [number, number, number, number];
  trait: number;
}

export interface SpawnFacts extends Genes {
  id: string;
  kind: 'wild' | 'weather' | 'landmark';
  lat: number;
  lng: number;
  expires: number;
  /** Wild only: the roll that lets terrain swap the species (water → Tide, green → Grove). */
  habitatRoll?: number;
}

const lngStep = (deg: number, row: number) => deg / Math.max(0.15, Math.cos(((row + 0.5) * deg * Math.PI) / 180));
const wrap = (lng: number) => (lng > 180 ? lng - 360 : lng < -180 ? lng + 360 : lng);

function rollGrade(rng: Mulberry32): number {
  const total = GRADE_WEIGHTS.reduce((a, b) => a + b, 0);
  let roll = rng.nextDouble() * total;
  for (let g = 0; g < GRADE_WEIGHTS.length; g++) {
    roll -= GRADE_WEIGHTS[g];
    if (roll <= 0) return g;
  }
  return 0;
}

function rollGenes(rng: Mulberry32, species: number, grade: number, minVigor = 0): Genes {
  const v = () => minVigor + rng.nextInt(16 - minVigor);
  const vigor: [number, number, number, number] = [v(), v(), v(), v()];
  return { species, grade, vigor, trait: rng.nextInt(TRAITS) };
}

/** Re-derives a wild spawn: `${row}:${col}:${window}:${i}`. */
export function wildSpawn(row: number, col: number, w: number, i: number): SpawnFacts | null {
  const step = lngStep(CELL_DEG, row);
  const rng = new Mulberry32(hash32(row, col, w, 1));
  const roll = rng.nextInt(100);
  const count = roll < 35 ? 0 : roll < 80 ? 1 : 2;
  for (let k = 0; k < count; k++) {
    const lat = (row + rng.nextDouble()) * CELL_DEG;
    const lng = wrap((col + rng.nextDouble()) * step);
    const sp = rng.nextInt(SPECIES.length);
    const grade = rollGrade(rng);
    const genes = rollGenes(rng, sp, grade);
    const habitatRoll = rng.nextDouble();
    if (k === i) {
      return { id: `${row}:${col}:${w}:${i}`, kind: 'wild', lat, lng, expires: (w + 1) * WINDOW_MS, habitatRoll, ...genes };
    }
  }
  return null;
}

/** Re-derives a weather spawn: `w${row}:${col}:${window}:${sky}`. [boosted] are Affinity indices. */
export function weatherSpawn(row: number, col: number, w: number, sky: Sky, boosted: number[]): SpawnFacts | null {
  if (boosted.length === 0) return null;
  const sorted = [...boosted].sort((a, b) => a - b);
  const step = lngStep(CELL_DEG, row);
  const rng = new Mulberry32(hash32(row, col, w, 100 + SKIES.indexOf(sky)));
  if (rng.nextDouble() >= 0.22) return null;
  const lat = (row + rng.nextDouble()) * CELL_DEG;
  const lng = wrap((col + rng.nextDouble()) * step);
  const sp = sorted[rng.nextInt(sorted.length)];
  let grade = rollGrade(rng);
  if (grade === 0) grade = 1;
  const genes = rollGenes(rng, sp, grade, 4);
  return { id: `w${row}:${col}:${w}:${sky}`, kind: 'weather', lat, lng, expires: (w + 1) * WINDOW_MS, ...genes };
}

/** Landmark zone (row, col) containing a point; mirrors SpawnEngine.landmarks. */
export function zoneAt(lat: number, lng: number): { row: number; col: number } {
  const row = Math.floor(lat / ZONE_DEG);
  return { row, col: Math.floor(lng / lngStep(ZONE_DEG, row)) };
}

/** South-west and north-east corners of a Landmark zone, in degrees. */
export function zoneBounds(row: number, col: number): { s: number; w: number; n: number; e: number } {
  const step = lngStep(ZONE_DEG, row);
  return { s: row * ZONE_DEG, w: col * step, n: (row + 1) * ZONE_DEG, e: (col + 1) * step };
}

/** Re-derives a Landmark: `L${row}:${col}:${day}`. */
export function landmarkSpawn(row: number, col: number, day: number): SpawnFacts {
  const step = lngStep(ZONE_DEG, row);
  const rng = new Mulberry32(hash32(row, col, day, 7));
  const lat = (row + 0.1 + rng.nextDouble() * 0.8) * ZONE_DEG;
  const lng = wrap((col + 0.1 + rng.nextDouble() * 0.8) * step);
  const sp = rng.nextInt(SPECIES.length);
  const grade = rng.nextDouble() < 0.2 ? 4 : 3;
  const genes = rollGenes(rng, sp, grade, 10);
  return { id: `L${row}:${col}:${day}`, kind: 'landmark', lat, lng, expires: (day + 1) * DAY_MS, ...genes };
}

/** Parses any spawn id and re-derives it. Weather spawns need the boosted set. */
export function spawnFromId(id: string, boosted: number[] = []): SpawnFacts | null {
  let m = /^(-?\d+):(-?\d+):(\d+):(\d)$/.exec(id);
  if (m) return wildSpawn(+m[1], +m[2], +m[3], +m[4]);
  m = /^w(-?\d+):(-?\d+):(\d+):([a-zA-Z]+)$/.exec(id);
  if (m && (SKIES as readonly string[]).includes(m[4])) return weatherSpawn(+m[1], +m[2], +m[3], m[4] as Sky, boosted);
  m = /^L(-?\d+):(-?\d+):(\d+)$/.exec(id);
  if (m) return landmarkSpawn(+m[1], +m[2], +m[3]);
  return null;
}

export const windowIndex = (ms: number) => Math.floor(ms / WINDOW_MS);
export const dayIndex = (ms: number) => Math.floor(ms / DAY_MS);
