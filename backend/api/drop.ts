import { bytesToHex, hexToBytes, keccak256 } from 'viem';
import { authenticate } from '../lib/auth.js';
import { dropClaimTypes, dropSpotTypes, drops, dropsAbi, monadTestnet, operator, publicClient } from '../lib/chain.js';
import { latLng, metres } from '../lib/geo.js';
import { hexIdAt } from '../lib/hexgrid.js';
import { fail, handler } from '../lib/http.js';
import { seal, unseal } from '../lib/seal.js';

const REACH_M = 25;
const WARM_M = 60;

/**
 * Dead Drops, one endpoint (the Hobby plan caps functions at 12):
 * - { lat, lng }: seals the spot the player stands at and signs it with its
 *   hex, for TerrakinDrops.drop.
 * - { lat, lng, dropId }: unseals that drop's spot and signs a claim when the
 *   player stands within 25 m. Further away it only says "warm" (within 60 m)
 *   or "cold", never a distance.
 */
export default handler('POST', async (req) => {
  const { wallet } = await authenticate(req.headers.authorization);
  const { lat, lng } = latLng(req.body, fail);
  const contract = drops();
  if (!contract) fail(503, 'Dead drops are not deployed yet');
  const dropId = (req.body as { dropId?: unknown }).dropId;
  return dropId === undefined ? spotHere(wallet, lat, lng, contract) : claimHere(wallet, lat, lng, contract, dropId);
});

async function spotHere(wallet: `0x${string}`, lat: number, lng: number, contract: `0x${string}`) {
  const sealedSpot = bytesToHex(seal(Math.round(lat * 1e6), Math.round(lng * 1e6)));
  const spot = {
    player: wallet,
    hexId: hexIdAt(lat, lng),
    sealedHash: keccak256(sealedSpot),
    deadline: BigInt(Math.floor(Date.now() / 1000) + 600),
  };
  const signature = await operator().signTypedData({
    domain: { name: 'Terrakin Drops', version: '1', chainId: monadTestnet.id, verifyingContract: contract },
    types: dropSpotTypes,
    primaryType: 'Spot',
    message: spot,
  });
  return { spot: { ...spot, hexId: spot.hexId.toString(), deadline: spot.deadline.toString() }, sealedSpot, signature };
}

async function claimHere(wallet: `0x${string}`, lat: number, lng: number, contract: `0x${string}`, raw: unknown) {
  if (typeof raw !== 'string' || !/^\d{1,78}$/.test(raw)) fail(400, 'dropId is required');
  const dropId = BigInt(raw);
  const [info, sealedSpot] = await Promise.all([
    publicClient.readContract({ address: contract, abi: dropsAbi, functionName: 'info', args: [dropId] }),
    publicClient.readContract({ address: contract, abi: dropsAbi, functionName: 'sealedSpotOf', args: [dropId] }),
  ]);
  const [dropper, forWho, , expiresAt, done] = info;
  if (dropper === '0x0000000000000000000000000000000000000000' || done || Number(expiresAt) * 1000 < Date.now()) {
    fail(410, 'That drop is gone');
  }
  if (dropper.toLowerCase() === wallet.toLowerCase()) fail(403, 'That’s your own drop');
  if (forWho !== '0x0000000000000000000000000000000000000000' && forWho.toLowerCase() !== wallet.toLowerCase()) {
    fail(403, 'This drop is meant for someone else');
  }
  const spot = unseal(hexToBytes(sealedSpot));
  const d = metres(lat, lng, spot.lat, spot.lng);
  if (d > REACH_M) return { found: false, warm: d <= WARM_M };
  const claim = { player: wallet, dropId, deadline: BigInt(Math.floor(Date.now() / 1000) + 120) };
  const signature = await operator().signTypedData({
    domain: { name: 'Terrakin Drops', version: '1', chainId: monadTestnet.id, verifyingContract: contract },
    types: dropClaimTypes,
    primaryType: 'Claim',
    message: claim,
  });
  return { found: true, claim: { ...claim, dropId: raw, deadline: claim.deadline.toString() }, signature };
}
