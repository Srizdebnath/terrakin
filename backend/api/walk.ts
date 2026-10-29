import { authenticate } from '../lib/auth.js';
import { monadTestnet, operator, strides, walkTypes } from '../lib/chain.js';
import { latLng } from '../lib/geo.js';
import { fail, handler } from '../lib/http.js';
import { WalkError, makeWalkStamp, measureWalk, type WalkStamp } from '../lib/walk.js';

/**
 * Walk rewards, one endpoint (the Hobby plan caps functions at 12):
 * - { lat, lng }: stamps where the player is now. The app asks every ~100 m.
 * - { stamps }: measures the walk and signs a TerrakinStrides.Walk covering
 *   its whole 500 m steps.
 */
export default handler('POST', async (req) => {
  const { wallet } = await authenticate(req.headers.authorization);
  const contract = strides();
  if (!contract) fail(503, 'Walk rewards are not deployed yet');
  const stamps = (req.body as { stamps?: WalkStamp[] } | undefined)?.stamps;
  if (!stamps) {
    const { lat, lng } = latLng(req.body, fail);
    return makeWalkStamp(wallet, lat, lng, Math.floor(Date.now() / 1000));
  }
  let walk;
  try {
    walk = measureWalk(wallet, stamps, Math.floor(Date.now() / 1000));
  } catch (e) {
    if (e instanceof WalkError) fail(422, e.message);
    throw e;
  }
  const message = {
    player: wallet,
    from: BigInt(walk.from),
    to: BigInt(walk.to),
    metres: walk.metres,
    deadline: BigInt(Math.floor(Date.now() / 1000) + 180),
  };
  const signature = await operator().signTypedData({
    domain: { name: 'Terrakin Strides', version: '1', chainId: monadTestnet.id, verifyingContract: contract },
    types: walkTypes,
    primaryType: 'Walk',
    message,
  });
  return {
    walk: { player: wallet, from: walk.from, to: walk.to, metres: walk.metres, deadline: message.deadline.toString() },
    keepFrom: walk.keepFrom,
    signature,
  };
});
