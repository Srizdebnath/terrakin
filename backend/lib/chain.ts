import { createPublicClient, createWalletClient, defineChain, http, parseAbi } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

// Chain-agnostic: any EVM chain works by setting CHAIN_ID, RPC_URL and
// EXPLORER_URL (the app reads them from /api/config). Defaults: Monad testnet.
export const monadTestnet = defineChain({
  id: Number(process.env.CHAIN_ID ?? 10143),
  name: process.env.CHAIN_NAME ?? 'Monad Testnet',
  nativeCurrency: { name: 'Monad', symbol: process.env.CHAIN_SYMBOL ?? 'MON', decimals: 18 },
  rpcUrls: { default: { http: [process.env.RPC_URL ?? 'https://testnet-rpc.monad.xyz'] } },
  blockExplorers: { default: { name: 'Explorer', url: process.env.EXPLORER_URL ?? 'https://testnet.monadexplorer.com' } },
});

export const gameAbi = parseAbi([
  'function fund(address player)',
  'function funded(address) view returns (bool)',
  'function signer() view returns (address)',
]);

export const game = () => process.env.GAME_ADDRESS as `0x${string}`;
export const territory = () => process.env.TERRITORY_ADDRESS as `0x${string}`;
export const convergence = () => process.env.CONVERGENCE_ADDRESS as `0x${string}` | undefined;
export const drops = () => process.env.DROPS_ADDRESS as `0x${string}` | undefined;
export const strides = () => process.env.STRIDES_ADDRESS as `0x${string}` | undefined;
export const operator = () => privateKeyToAccount(process.env.OPERATOR_KEY as `0x${string}`);
export const publicClient = createPublicClient({ chain: monadTestnet, transport: http() });
export const walletClient = () => createWalletClient({ chain: monadTestnet, transport: http(), account: operator() });

/** EIP-712 shape of Terrakin.Bond; must match BOND_TYPEHASH in Terrakin.sol. */
export const bondTypes = {
  Bond: [
    { name: 'player', type: 'address' },
    { name: 'spawnId', type: 'bytes32' },
    { name: 'species', type: 'uint8' },
    { name: 'grade', type: 'uint8' },
    { name: 'vigor', type: 'uint32' },
    { name: 'trait', type: 'uint8' },
    { name: 'landmark', type: 'bool' },
    { name: 'lat', type: 'int32' },
    { name: 'lng', type: 'int32' },
    { name: 'hexId', type: 'uint64' },
    { name: 'zone', type: 'uint64' },
    { name: 'deadline', type: 'uint64' },
  ],
} as const;

/** EIP-712 shape of TerrakinTerritory.Presence. */
export const presenceTypes = {
  Presence: [
    { name: 'player', type: 'address' },
    { name: 'hexId', type: 'uint64' },
    { name: 'deadline', type: 'uint64' },
  ],
} as const;

/** EIP-712 shape of TerrakinTerritory.claimLoop; trail and inside are keccak256(abi.encodePacked(uint64[])), which pads each id to 32 bytes. */
export const loopTypes = {
  Loop: [
    { name: 'player', type: 'address' },
    { name: 'startedAt', type: 'uint64' },
    { name: 'trail', type: 'bytes32' },
    { name: 'inside', type: 'bytes32' },
    { name: 'deadline', type: 'uint64' },
  ],
} as const;

/** EIP-712 shape of TerrakinConvergence.Pass. */
export const convergencePassTypes = {
  Pass: [
    { name: 'player', type: 'address' },
    { name: 'eventId', type: 'bytes32' },
    { name: 'species', type: 'uint8' },
    { name: 'lat', type: 'int32' },
    { name: 'lng', type: 'int32' },
    { name: 'opensAt', type: 'uint64' },
    { name: 'deadline', type: 'uint64' },
  ],
} as const;

/** EIP-712 shapes of TerrakinDrops.Spot and .Claim. */
export const dropSpotTypes = {
  Spot: [
    { name: 'player', type: 'address' },
    { name: 'hexId', type: 'uint64' },
    { name: 'sealedHash', type: 'bytes32' },
    { name: 'deadline', type: 'uint64' },
  ],
} as const;

export const dropClaimTypes = {
  Claim: [
    { name: 'player', type: 'address' },
    { name: 'dropId', type: 'uint256' },
    { name: 'deadline', type: 'uint64' },
  ],
} as const;

export const dropsAbi = parseAbi([
  'function sealedSpotOf(uint256 id) view returns (bytes)',
  'function info(uint256 id) view returns (address dropper, address forWho, uint64 hexId, uint64 expiresAt, bool done, uint256 kinId, uint256 mon, string riddle)',
]);

/** EIP-712 shape of TerrakinStrides.Walk. */
export const walkTypes = {
  Walk: [
    { name: 'player', type: 'address' },
    { name: 'from', type: 'uint64' },
    { name: 'to', type: 'uint64' },
    { name: 'metres', type: 'uint32' },
    { name: 'deadline', type: 'uint64' },
  ],
} as const;
