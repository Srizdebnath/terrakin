import { authenticate } from '../lib/auth.js';
import { handler } from '../lib/http.js';
import { enroll } from '../lib/season.js';

/** Joins the season leaderboards (free: the operator pays). Idempotent. */
export default handler('POST', async (req) => {
  const { wallet } = await authenticate(req.headers.authorization);
  await enroll(wallet);
  return { wallet, enrolled: true };
});
