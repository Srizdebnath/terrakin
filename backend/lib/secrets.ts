import { createHmac } from 'node:crypto';

/**
 * Purpose-bound 32-byte keys derived from the operator key, so features that
 * need a server secret (walk stamps, sealed drop spots) add no new env vars.
 * Rotating OPERATOR_KEY invalidates unclaimed drop spots, so don't.
 */
export function derivedKey(purpose: 'loop-stamps' | 'drop-spots'): Uint8Array {
  const key = process.env.OPERATOR_KEY;
  if (!key) throw new Error('OPERATOR_KEY is not set');
  return createHmac('sha256', key).update(`terrakin:${purpose}`).digest() as Uint8Array;
}
