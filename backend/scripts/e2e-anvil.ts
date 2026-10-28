// End-to-end on local Anvil: vouchers and presence proofs signed with the
// backend's EIP-712 shapes and hex maths are accepted by the deployed contracts.
//   anvil --port 8645 --chain-id 10143 &
//   (cd ../contracts && OPERATOR_KEY=0xac09…ff80 POOL=5000000000000000000 forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8645 --broadcast)
//   GAME_ADDRESS=… TERRITORY_ADDRESS=… node --experimental-strip-types scripts/e2e-anvil.ts
import { createPublicClient, createWalletClient, http, parseAbi, keccak256, toBytes, defineChain, parseEther } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { bondTypes, presenceTypes } from '../lib/chain.ts';
import { hexIdAtE6, zoneOf } from '../lib/hexgrid.ts';
import { spawnFromId } from '../lib/spawn.ts';

const chain = defineChain({ id: 10143, name: 'anvil', nativeCurrency: { name: 'MON', symbol: 'MON', decimals: 18 }, rpcUrls: { default: { http: ['http://127.0.0.1:8645'] } } });
const GAME = process.env.GAME_ADDRESS as `0x${string}`;
const LAND = process.env.TERRITORY_ADDRESS as `0x${string}`;
const op = privateKeyToAccount('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80');
const alice = privateKeyToAccount('0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d');
const bob = privateKeyToAccount('0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a');
const pub = createPublicClient({ chain, transport: http() });
const wallet = (account: typeof op) => createWalletClient({ chain, transport: http(), account });
const abi = parseAbi([
  'function fund(address)',
  'function createProfile(string,uint8) payable returns (uint256)',
  'struct Bond { address player; bytes32 spawnId; uint8 species; uint8 grade; uint32 vigor; uint8 trait; bool landmark; int32 lat; int32 lng; uint64 hexId; uint64 zone; uint64 deadline; }',
  'function bond(Bond v, bytes sig, uint32[4] orbsUsed) returns (uint256)',
  'function kinOf(address) view returns (uint256[] ids, (uint8,uint8,uint8,bool,uint16,uint40,int32,int32,uint8[4],uint16[4])[] data)',
]);
const landAbi = parseAbi([
  'struct Presence { address player; uint64 hexId; uint64 deadline; }',
  'function claim(Presence p, bytes sig, uint256[] kin) payable',
  'function hexes(uint64) view returns (address owner, uint40 since, uint40 shieldUntil)',
]);
const wait = async (h: `0x${string}`) => {
  const r = await pub.waitForTransactionReceipt({ hash: h });
  if (r.status !== 'success') throw new Error(`reverted ${h}`);
  return r;
};
const check = (ok: boolean, what: string) => {
  if (!ok) throw new Error(`FAILED: ${what}`);
  console.log('ok', what);
};

async function bondAs(who: typeof op, spawnId: string) {
  const s = spawnFromId(spawnId)!;
  const lat = Math.round(s.lat * 1e6);
  const lng = Math.round(s.lng * 1e6);
  const [row, col] = s.kind === 'landmark' ? s.id.slice(1).split(':').map(Number) : [0, 0];
  const v = {
    player: who.address, spawnId: keccak256(toBytes(s.id)), species: s.species, grade: s.grade,
    vigor: s.vigor[0] | (s.vigor[1] << 8) | (s.vigor[2] << 16) | (s.vigor[3] << 24), trait: s.trait,
    landmark: s.kind === 'landmark', lat, lng, hexId: hexIdAtE6(lat, lng),
    zone: s.kind === 'landmark' ? zoneOf(row, col) : 0n, deadline: BigInt(Math.floor(Date.now() / 1000) + 600),
  };
  const sig = await op.signTypedData({ domain: { name: 'Terrakin', version: '1', chainId: 10143, verifyingContract: GAME }, types: bondTypes, primaryType: 'Bond', message: v });
  const r = await wait(await wallet(who).writeContract({ address: GAME, abi, functionName: 'bond', args: [v, sig, [1, 0, 0, 0]] }));
  return { r, hexId: v.hexId, lat: s.lat, lng: s.lng };
}

for (const [who, name] of [[alice, 'alice'], [bob, 'bobby']] as const) {
  await wait(await wallet(op).writeContract({ address: GAME, abi, functionName: 'fund', args: [who.address] }));
  await wait(await wallet(who).writeContract({ address: GAME, abi, functionName: 'createProfile', args: [name, 2], value: parseEther('0.02') }));
}

const first = await bondAs(alice, 'L579:2164:20388');
console.log('landmark bond gasUsed', first.r.gasUsed);
const [ids] = await pub.readContract({ address: GAME, abi, functionName: 'kinOf', args: [alice.address] });
check(ids.length === 1, 'bond voucher with hex + zone accepted');

const presence = { player: alice.address, hexId: first.hexId, deadline: BigInt(Math.floor(Date.now() / 1000) + 120) };
const psig = await op.signTypedData({ domain: { name: 'Terrakin Territory', version: '1', chainId: 10143, verifyingContract: LAND }, types: presenceTypes, primaryType: 'Presence', message: presence });
const c = await wait(await wallet(alice).writeContract({ address: LAND, abi: landAbi, functionName: 'claim', args: [presence, psig, [ids[0]]], value: parseEther('0.01') }));
console.log('claim gasUsed', c.gasUsed);
const [owner] = await pub.readContract({ address: LAND, abi: landAbi, functionName: 'hexes', args: [first.hexId] });
check(owner === alice.address, 'presence proof accepted, hex claimed');

// Bob catches the same Landmark in Alice's hex; no auction today, so Alice
// takes the 10% hex cut.
const before = await pub.getBalance({ address: alice.address });
await bondAs(bob, 'L579:2164:20388');
const gained = (await pub.getBalance({ address: alice.address })) - before;
check(gained > 0n, `hex owner earned a cut (${gained} wei)`);
