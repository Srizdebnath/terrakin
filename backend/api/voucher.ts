import { keccak256, toBytes } from 'viem';
import { authenticate } from '../lib/auth.js';
import { bondTypes, game, monadTestnet, operator } from '../lib/chain.js';
import { hexIdAtE6, zoneOf } from '../lib/hexgrid.js';
import { fail, handler } from '../lib/http.js';
import { reserveMythic } from '../lib/season.js';
import { spawnFromId, SPECIES } from '../lib/spawn.js';
import { weatherAt } from '../lib/weather.js';

const MAX_REACH_M = 95; // 40 m base + perks + buddy + GPS slack
const GRACE_MS = 2 * 60 * 1000;
const TIDE = 1;
const GROVE = 0;

function metres(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const r = 6371008.8;
  const dLat = ((bLat - aLat) * Math.PI) / 180;
  const dLng = ((bLng - aLng) * Math.PI) / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos((aLat * Math.PI) / 180) * Math.cos((bLat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

/**
 * Signs a bond voucher after re-deriving the spawn from its id and checking
 * the player stands next to it before it expires.
 *
 * Body: { spawnId, species, lat, lng, boosted? } — lat/lng are the player's GPS.
 */
export default handler('POST', async (req) => {
  const { wallet } = await authenticate(req.headers.authorization);
  const b = (req.body ?? {}) as { spawnId?: string; species?: number; lat?: number; lng?: number; boosted?: number[] };
  if (typeof b.spawnId !== 'string' || typeof b.species !== 'number' || typeof b.lat !== 'number' || typeof b.lng !== 'number') {
    fail(400, 'spawnId, species, lat and lng are required');
  }

  let boosted: number[] = [];
  if (b.spawnId.startsWith('w')) {
    boosted = (b.boosted ?? []).filter((x) => Number.isInteger(x) && x >= 0 && x < SPECIES.length);
    const sky = b.spawnId.split(':').pop();
    const w = await weatherAt(b.lat, b.lng);
    if (w.sky !== sky) fail(409, 'The weather has changed; that Kin has moved on');
    if (boosted.length === 0 || boosted.some((x) => !w.plausible.has(x))) fail(409, 'Weather boost does not match');
  }

  const s = spawnFromId(b.spawnId, boosted);
  if (!s) fail(404, 'No such Kin');
  const now = Date.now();
  if (now > s.expires + GRACE_MS) fail(410, 'This Kin has already left');
  const d = metres(b.lat, b.lng, s.lat, s.lng);
  if (d > MAX_REACH_M) fail(403, `Too far away (${Math.round(d)} m)`);

  // Terrain may have swapped a wild Kin's species on the phone; allow only
  // the swaps its habitat roll permits.
  const ok =
    b.species === s.species ||
    (s.kind === 'wild' && b.species === TIDE && s.species !== TIDE && (s.habitatRoll ?? 1) < 0.6) ||
    (s.kind === 'wild' && b.species === GROVE && s.species !== GROVE && (s.habitatRoll ?? 1) < 0.35);
  if (!ok) fail(409, 'Species does not match this spawn');

  // Mythics are capped per species per season: reserve a numbered slot on
  // chain, or bond it as Epic once the species has sold out.
  const MYTHIC = 4;
  let grade = s.grade;
  let mythic: { serial: number; cap: number } | null | undefined;
  if (grade === MYTHIC) {
    mythic = await reserveMythic(wallet, b.species, keccak256(toBytes(s.id)));
    if (mythic === null) grade = MYTHIC - 1;
  }

  const lat = Math.round(s.lat * 1e6);
  const lng = Math.round(s.lng * 1e6);
  // Landmark ids are L<row>:<col>:<day>; the zone is what its auction is for.
  const [row, col] = s.kind === 'landmark' ? s.id.slice(1).split(':').map(Number) : [0, 0];
  const voucher = {
    player: wallet,
    spawnId: keccak256(toBytes(s.id)),
    species: b.species,
    grade,
    vigor: s.vigor[0] | (s.vigor[1] << 8) | (s.vigor[2] << 16) | (s.vigor[3] << 24),
    trait: s.trait,
    landmark: s.kind === 'landmark',
    lat,
    lng,
    hexId: hexIdAtE6(lat, lng),
    zone: s.kind === 'landmark' ? zoneOf(row, col) : 0n,
    deadline: BigInt(Math.floor(now / 1000) + 600),
  };
  const signature = await operator().signTypedData({
    domain: { name: 'Terrakin', version: '1', chainId: monadTestnet.id, verifyingContract: game() },
    types: bondTypes,
    primaryType: 'Bond',
    message: voucher,
  });
  return {
    voucher: { ...voucher, hexId: voucher.hexId.toString(), zone: voucher.zone.toString(), deadline: voucher.deadline.toString() },
    signature,
    mythic: mythic === undefined ? undefined : mythic === null ? { soldOut: true } : mythic,
  };
});
