import { PrivyClient } from '@privy-io/node';

let client: PrivyClient | undefined;
const privy = () =>
  (client ??= new PrivyClient({ appId: process.env.PRIVY_APP_ID!, appSecret: process.env.PRIVY_APP_SECRET! }));

export class AuthError extends Error {}

/**
 * Verifies the Privy access token from `Authorization: Bearer …` and returns
 * the player's embedded Ethereum wallet. The wallet always comes from Privy,
 * never from the request body.
 */
export async function authenticate(authorization: string | undefined): Promise<{ userId: string; wallet: `0x${string}` }> {
  const token = authorization?.startsWith('Bearer ') ? authorization.slice(7) : undefined;
  if (!token) throw new AuthError('Missing access token');
  let userId: string;
  try {
    ({ user_id: userId } = await privy().utils().auth().verifyAccessToken(token));
  } catch {
    throw new AuthError('Invalid or expired access token');
  }
  const user = await privy().users()._get(userId);
  const wallet = (user.linked_accounts as unknown as Array<Record<string, unknown>>).find(
    (a) => a.type === 'wallet' && a.wallet_client_type === 'privy' && a.chain_type === 'ethereum',
  );
  if (!wallet?.address) throw new AuthError('No embedded wallet yet');
  return { userId, wallet: wallet.address as `0x${string}` };
}
