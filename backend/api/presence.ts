import { authenticate } from '../lib/auth.js';
import { monadTestnet, operator, presenceTypes, territory } from '../lib/chain.js';
import { hexIdAt } from '../lib/hexgrid.js';
import { fail, handler } from '../lib/http.js';

/**
 * Signs a short-lived proof that the player stands in a territory hex, which
 * TerrakinTerritory requires to claim or attack it. The hex comes from the
 * player's GPS, computed here, never from the request.
 *
 * Body: { lat, lng } in degrees.
 */
export default handler('POST', async (req) => {
  const { wallet } = await authenticate(req.headers.authorization);
  const b = (req.body ?? {}) as { lat?: number; lng?: number };
  if (typeof b.lat !== 'number' || typeof b.lng !== 'number' || Math.abs(b.lat) > 85 || Math.abs(b.lng) > 180) {
    fail(400, 'lat and lng are required');
  }
  const presence = {
    player: wallet,
    hexId: hexIdAt(b.lat, b.lng),
    deadline: BigInt(Math.floor(Date.now() / 1000) + 120),
  };
  const signature = await operator().signTypedData({
    domain: { name: 'Terrakin Territory', version: '2', chainId: monadTestnet.id, verifyingContract: territory() },
    types: presenceTypes,
    primaryType: 'Presence',
    message: presence,
  });
  return { presence: { ...presence, hexId: presence.hexId.toString(), deadline: presence.deadline.toString() }, signature };
});
