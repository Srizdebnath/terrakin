import { authenticate } from '../lib/auth.js';
import { game, gameAbi, publicClient, walletClient } from '../lib/chain.js';
import { fail, handler } from '../lib/http.js';
import { enroll } from '../lib/season.js';

/**
 * Starter grant: the contract sends the MON and welcome orbs, and remembers
 * the wallet so it can only ever be funded once.
 */
export default handler('POST', async (req) => {
  const { wallet } = await authenticate(req.headers.authorization);
  if (!game()) fail(503, 'Game contract not deployed yet');
  const already = await publicClient.readContract({ address: game(), abi: gameAbi, functionName: 'funded', args: [wallet] });
  if (already) {
    await enroll(wallet);
    return { wallet, funded: true, tx: null };
  }
  const client = walletClient();
  const { request } = await publicClient.simulateContract({
    address: game(),
    abi: gameAbi,
    functionName: 'fund',
    args: [wallet],
    account: client.account,
  });
  const tx = await client.writeContract(request);
  const receipt = await publicClient.waitForTransactionReceipt({ hash: tx, timeout: 20_000 });
  if (receipt.status !== 'success') fail(502, 'Funding transaction reverted');
  await enroll(wallet);
  return { wallet, funded: true, tx };
});
