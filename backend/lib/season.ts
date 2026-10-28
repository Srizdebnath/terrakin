import { BaseError, ContractFunctionRevertedError, parseAbi } from 'viem';
import { publicClient, walletClient } from './chain.js';

export const season = () => process.env.SEASON_ADDRESS as `0x${string}` | undefined;

const seasonAbi = parseAbi([
  'function enrolled(address) view returns (bool)',
  'function enrollFor(address player)',
  'function reserveMythic(address player, uint8 species, bytes32 spawnId) returns (uint16 serial)',
  'function mythicCap() view returns (uint16)',
  'error SoldOut()',
  'error SeasonOver()',
]);

/** Adds a player to the season registry (the leaderboards), at the operator's cost. */
export async function enroll(player: `0x${string}`): Promise<void> {
  const s = season();
  if (!s) return;
  if (await publicClient.readContract({ address: s, abi: seasonAbi, functionName: 'enrolled', args: [player] })) return;
  const client = walletClient();
  const hash = await client.writeContract({ address: s, abi: seasonAbi, functionName: 'enrollFor', args: [player], chain: client.chain });
  await publicClient.waitForTransactionReceipt({ hash, timeout: 20_000 });
}

/**
 * Reserves the next numbered Mythic of [species] for this spawn, on chain.
 * Returns the serial and cap, or null when the species is sold out for the
 * season (or the season is over): the caller then signs the Kin as Epic.
 */
export async function reserveMythic(
  player: `0x${string}`,
  species: number,
  spawnId: `0x${string}`,
): Promise<{ serial: number; cap: number } | null> {
  const s = season();
  if (!s) return { serial: 0, cap: 0 }; // seasons not deployed: uncapped
  const client = walletClient();
  try {
    const { request, result } = await publicClient.simulateContract({
      address: s,
      abi: seasonAbi,
      functionName: 'reserveMythic',
      args: [player, species, spawnId],
      account: client.account,
    });
    const hash = await client.writeContract(request);
    const receipt = await publicClient.waitForTransactionReceipt({ hash, timeout: 20_000 });
    if (receipt.status !== 'success') throw new Error('Mythic reservation reverted');
    const cap = await publicClient.readContract({ address: s, abi: seasonAbi, functionName: 'mythicCap' });
    return { serial: result, cap };
  } catch (e) {
    const revert = e instanceof BaseError ? e.walk((x) => x instanceof ContractFunctionRevertedError) : null;
    const name = revert instanceof ContractFunctionRevertedError ? revert.data?.errorName : undefined;
    if (name === 'SoldOut' || name === 'SeasonOver') return null;
    throw e;
  }
}
