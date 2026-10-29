import type { VercelRequest, VercelResponse } from '@vercel/node';
import { authenticate } from '../lib/auth.js';
import { convergence, convergencePassTypes, monadTestnet, operator } from '../lib/chain.js';
import { ANNOUNCE_MS, REACH_M, WINDOW_MS, convergencesNear, scheduleNear } from '../lib/convergence.js';
import { latLng, latLngFromQuery, metres } from '../lib/geo.js';
import { fail, handler } from '../lib/http.js';

/**
 * GET ?lat=&lng=: the Convergence schedule for the player's zone, today's
 * (until it closes) and tomorrow's. No auth: it's public, like a poster.
 */
const schedule = handler('GET', async (req) => {
  const { lat, lng } = latLngFromQuery(req.query, fail);
  const now = Date.now();
  const events = await scheduleNear(lat, lng, now);
  return {
    now,
    windowMs: WINDOW_MS,
    announceMs: ANNOUNCE_MS,
    reachM: REACH_M,
    events: events.map((c) => ({
      id: c.id,
      key: c.key,
      name: c.place.name,
      lat: c.place.lat,
      lng: c.place.lng,
      species: c.species,
      opensAt: c.opensAt,
    })),
  };
});

/**
 * POST { lat, lng, id }: signs a pass into a Convergence circle when the
 * player stands within reach of its place while it's open.
 */
const pass = handler('POST', async (req) => {
  const { wallet } = await authenticate(req.headers.authorization);
  const { lat, lng } = latLng(req.body, fail);
  const id = (req.body as { id?: string }).id;
  const contract = convergence();
  if (!contract) fail(503, 'Convergence is not deployed yet');
  const now = Date.now();
  const c = (await convergencesNear(lat, lng, now)).find((e) => e.id === id);
  if (!c) fail(404, 'No such Convergence near you');
  if (now < c.opensAt) fail(403, 'It hasn’t opened yet');
  if (now >= c.opensAt + WINDOW_MS) fail(403, 'It’s over');
  const d = metres(lat, lng, c.place.lat, c.place.lng);
  if (d > REACH_M) fail(403, `Get to ${c.place.name} first (${Math.round(d)} m away)`);
  const pass = {
    player: wallet,
    eventId: c.id,
    species: c.species,
    lat: Math.round(c.place.lat * 1e6),
    lng: Math.round(c.place.lng * 1e6),
    opensAt: BigInt(Math.floor(c.opensAt / 1000)),
    deadline: BigInt(Math.floor(now / 1000) + 120),
  };
  const signature = await operator().signTypedData({
    domain: { name: 'Terrakin Convergence', version: '1', chainId: monadTestnet.id, verifyingContract: contract },
    types: convergencePassTypes,
    primaryType: 'Pass',
    message: pass,
  });
  return { pass: { ...pass, opensAt: pass.opensAt.toString(), deadline: pass.deadline.toString() }, signature };
});

// One function for both (the Hobby plan caps functions at 12).
export default (req: VercelRequest, res: VercelResponse) => (req.method === 'GET' ? schedule : pass)(req, res);
