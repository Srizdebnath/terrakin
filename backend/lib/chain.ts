import { createPublicClient, createWalletClient, defineChain, http, parseAbi } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

export const monadTestnet = defineChain({
  id: 10143,
  name: 'Monad Testnet',
  nativeCurrency: { name: 'Monad', symbol: 'MON', decimals: 18 },
  rpcUrls: { default: { http: [process.env.RPC_URL ?? 'https://testnet-rpc.monad.xyz'] } },
  blockExplorers: { default: { name: 'Monad Explorer', url: 'https://testnet.monadexplorer.com' } },
});

export const gameAbi = parseAbi([
  'function fund(address player)',
  'function funded(address) view returns (bool)',
  'function signer() view returns (address)',
]);

export const game = () => process.env.GAME_ADDRESS as `0x${string}`;
export const territory = () => process.env.TERRITORY_ADDRESS as `0x${string}`;
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
