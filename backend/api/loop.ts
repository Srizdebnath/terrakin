import { encodePacked, keccak256 } from 'viem';
import { authenticate } from '../lib/auth.js';
import { loopTypes, monadTestnet, operator, territory } from '../lib/chain.js';
import { fail, handler } from '../lib/http.js';
import { LoopError, closeLoop, makeStamp, type Stamp } from '../lib/loop.js';
import { latLng } from '../lib/geo.js';
import { hexIdAt } from '../lib/hexgrid.js';

/**
 * Loop Capture, one endpoint (the Hobby plan caps functions at 12):
 * - { lat, lng }: stamps the hex the player is walking through. The app asks
 *   on entering each new hex and keeps the stamps until it closes the loop.
 * - { stamps }: checks the walk (in order, ending back in the first hex) and
 *   signs its trail and the hexes it encloses for TerritoryV2.claimLoop.
 */
export default handler('POST', async (req) => {
  const { wallet } = await authenticate(req.headers.authorization);
  const stamps = (req.body as { stamps?: Stamp[] } | undefined)?.stamps;
  if (!stamps) {
    const { lat, lng } = latLng(req.body, fail);
    return makeStamp(wallet, hexIdAt(lat, lng), Math.floor(Date.now() / 1000));
  }
  let loop;
  try {
    loop = closeLoop(wallet, stamps, Math.floor(Date.now() / 1000));
  } catch (e) {
    if (e instanceof LoopError) fail(422, e.message);
    throw e;
  }
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 180);
  // Solidity's abi.encodePacked pads array elements to 32 bytes, even uint64.
  const pack = (ids: bigint[]) => keccak256(encodePacked(ids.map(() => 'uint256' as const), ids));
  const signature = await operator().signTypedData({
    domain: { name: 'Terrakin Territory', version: '2', chainId: monadTestnet.id, verifyingContract: territory() },
    types: loopTypes,
    primaryType: 'Loop',
    message: {
      player: wallet,
      startedAt: BigInt(loop.startedAt),
      trail: pack(loop.trail),
      inside: pack(loop.inside),
      deadline,
    },
  });
  return {
    startedAt: loop.startedAt,
    deadline: deadline.toString(),
    trail: loop.trail.map(String),
    inside: loop.inside.map(String),
    signature,
  };
});
