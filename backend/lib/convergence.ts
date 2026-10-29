import { keccak256, toBytes } from 'viem';
import { DAY_MS, SPECIES, hash32, zoneAt, zoneBounds } from './spawn.js';

// Convergence: once a day per Landmark zone, a Mythic appears for 20 minutes
// at a named public place (park, square, pedestrian plaza) from OpenStreetMap,
// announced an hour ahead. The schedule is derived from (zone, day), so every
// server instance and the app agree without storage.

export const WINDOW_MS = 20 * 60 * 1000; // TerrakinConvergence.WINDOW
export const ANNOUNCE_MS = 60 * 60 * 1000;
export const REACH_M = 40;

export interface Place {
  osmId: string;
  name: string;
  lat: number;
  lng: number;
}

export interface Convergence {
  id: `0x${string}`;
  key: string; // C{row}:{col}:{day}
  place: Place;
  species: number;
  opensAt: number; // ms
}

const NOMINATIM = 'https://nominatim.openstreetmap.org/search';
const cache = new Map<string, { at: number; places: Place[] }>();

/**
 * Named parks inside one zone, sorted by OSM id so picks are stable. Nominatim
 * asks for at most one request a second, so results are cached for a day.
 */
async function placesInZone(row: number, col: number): Promise<Place[]> {
  const k = `${row}:${col}`;
  const hit = cache.get(k);
  if (hit && Date.now() - hit.at < DAY_MS) return hit.places;
  const b = zoneBounds(row, col);
  const url = `${NOMINATIM}?q=park&viewbox=${b.w},${b.n},${b.e},${b.s}&bounded=1&format=jsonv2&limit=40`;
  const res = await fetch(url, {
    headers: { 'User-Agent': 'Terrakin/1.0 (https://terrakin.vercel.app)' },
    signal: AbortSignal.timeout(12000),
  });
  if (!res.ok) throw new Error(`Nominatim ${res.status}`);
  const j = (await res.json()) as Array<{ osm_type: string; osm_id: number; lat: string; lon: string; name?: string; category?: string }>;
  const places = j
    .filter((e) => e.category === 'leisure' && e.name)
    .map((e) => ({ osmId: `${e.osm_type}/${e.osm_id}`, name: e.name!, lat: +e.lat, lng: +e.lon }))
    .filter((p) => p.lat >= b.s && p.lat < b.n && p.lng >= b.w && p.lng < b.e)
    .sort((x, y) => (x.osmId < y.osmId ? -1 : x.osmId > y.osmId ? 1 : 0));
  cache.set(k, { at: Date.now(), places });
  return places;
}

/** Opening time: an hour between 11:00 and 20:00 local solar time. */
function opensAt(row: number, col: number, day: number, lng: number): number {
  const localHour = 11 + (hash32(row, col, day, 41) % 10);
  const offsetH = Math.round(lng / 15);
  return day * DAY_MS + (localHour - offsetH) * 60 * 60 * 1000;
}

export function eventId(key: string): `0x${string}` {
  return keccak256(toBytes(key));
}

/** The zone's convergence on [day], or null where there's no public place. */
function forZone(row: number, col: number, day: number, places: Place[]): Convergence | null {
  if (places.length === 0) return null;
  const b = zoneBounds(row, col);
  const place = places[hash32(row, col, day, 43) % places.length];
  const key = `C${row}:${col}:${day}`;
  return {
    id: eventId(key),
    key,
    place,
    species: hash32(row, col, day, 47) % SPECIES.length,
    opensAt: opensAt(row, col, day, (b.w + b.e) / 2),
  };
}

/** Convergences in the player's zone that are announced (opening within the hour) or open. */
export async function convergencesNear(lat: number, lng: number, nowMs: number): Promise<Convergence[]> {
  const { row, col } = zoneAt(lat, lng);
  const places = await placesInZone(row, col);
  const today = Math.floor(nowMs / DAY_MS);
  const out: Convergence[] = [];
  for (const day of [today - 1, today, today + 1]) {
    const c = forZone(row, col, day, places);
    if (c && nowMs >= c.opensAt - ANNOUNCE_MS && nowMs < c.opensAt + WINDOW_MS) out.push(c);
  }
  return out;
}

/** Today's and tomorrow's schedule for the zone, for the "next convergence" hint. */
export async function scheduleNear(lat: number, lng: number, nowMs: number): Promise<Convergence[]> {
  const { row, col } = zoneAt(lat, lng);
  const places = await placesInZone(row, col);
  const today = Math.floor(nowMs / DAY_MS);
  return [today, today + 1]
    .map((day) => forZone(row, col, day, places))
    .filter((c): c is Convergence => c !== null && nowMs < c.opensAt + WINDOW_MS);
}
