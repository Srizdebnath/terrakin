import { formatEther, parseAbi } from 'viem';
import { game, operator, publicClient } from '../lib/chain.js';
import { handler } from '../lib/http.js';

const pricesAbi = parseAbi(['function prices() view returns ((uint128 grant, uint128, uint128, uint128, uint128[4], uint128[5], uint32, uint32))']);
const FUND_GAS = 0.012; // MON the operator spends per fund() call

/** How many more players the pool and operator can fund. Top up when low. */
export default handler('GET', async () => {
  const [pool, op, prices] = await Promise.all([
    publicClient.getBalance({ address: game() }),
    publicClient.getBalance({ address: operator().address }),
    publicClient.readContract({ address: game(), abi: pricesAbi, functionName: 'prices' }),
  ]);
  const poolMon = Number(formatEther(pool));
  const opMon = Number(formatEther(op));
  const grant = Number(formatEther(prices[0])); // MON per new player (prices().grant)
  const playersLeft = Math.min(Math.floor(poolMon / grant), Math.floor(opMon / FUND_GAS));
  return {
    pool: { address: game(), mon: poolMon },
    operator: { address: operator().address, mon: opMon },
    playersLeft,
    status: playersLeft < 5 ? 'top up soon' : 'ok',
  };
});
