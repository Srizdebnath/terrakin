import { authenticate } from '../lib/auth.js';
import { monadTestnet, operator } from '../lib/chain.js';
import { zoneOf } from '../lib/hexgrid.js';
import { fail, handler } from '../lib/http.js';
import { dayIndex, landmarkSpawn, zoneAt } from '../lib/spawn.js';

const RAID_REACH_M = 150;

const passTypes = {
  Pass: [
    { name: 'player', type: 'address' },
    { name: 'zone', type: 'uint64' },
    { name: 'day', type: 'uint32' },
    { name: 'deadline', type: 'uint64' },
  ],
} as const;

function metres(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const r = 6371008.8;
  const dLat = ((bLat - aLat) * Math.PI) / 180;
  const dLng = ((bLng - aLng) * Math.PI) / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos((aLat * Math.PI) / 180) * Math.cos((bLat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

/**
 * Signs a raid pass when the player stands within 150 m of today's Landmark
 * (checking their zone and its neighbours, since a Landmark near an edge may
 * sit across it). Body: { lat, lng }.
 */
export default handler('POST', async (req) => {
  const { wallet } = await authenticate(req.headers.authorization);
  const b = (req.body ?? {}) as { lat?: number; lng?: number };
  if (typeof b.lat !== 'number' || typeof b.lng !== 'number') fail(400, 'lat and lng are required');
  const raids = process.env.RAIDS_ADDRESS as `0x${string}` | undefined;
  if (!raids) fail(503, 'Raids are not deployed yet');
  const day = dayIndex(Date.now());
  const { row, col } = zoneAt(b.lat, b.lng);
  let best: { row: number; col: number; d: number } | null = null;
  for (let dr = -1; dr <= 1; dr++) {
    for (let dc = -1; dc <= 1; dc++) {
      const s = landmarkSpawn(row + dr, col + dc, day);
      const d = metres(b.lat, b.lng, s.lat, s.lng);
      if (!best || d < best.d) best = { row: row + dr, col: col + dc, d };
    }
  }
  if (!best || best.d > RAID_REACH_M) fail(403, `Get to the Landmark first (${Math.round(best?.d ?? 0)} m away)`);
  const pass = {
    player: wallet,
    zone: zoneOf(best.row, best.col),
    day,
    deadline: BigInt(Math.floor(Date.now() / 1000) + 120),
  };
  const signature = await operator().signTypedData({
    domain: { name: 'Terrakin Raids', version: '1', chainId: monadTestnet.id, verifyingContract: raids },
    types: passTypes,
    primaryType: 'Pass',
    message: pass,
  });
  return { pass: { ...pass, zone: pass.zone.toString(), deadline: pass.deadline.toString() }, signature };
});
