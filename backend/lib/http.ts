import type { VercelRequest, VercelResponse } from '@vercel/node';

/** JSON handler wrapper: method check, CORS-free (native app only), error mapping. */
export function handler(method: 'GET' | 'POST', fn: (req: VercelRequest) => Promise<unknown>) {
  return async (req: VercelRequest, res: VercelResponse) => {
    if (req.method !== method) return res.status(405).json({ error: 'Method not allowed' });
    try {
      res.status(200).json(await fn(req));
    } catch (e) {
      const err = e as Error & { status?: number };
      const status = err.status ?? (err.name === 'AuthError' || err.constructor?.name === 'AuthError' ? 401 : 500);
      if (status >= 500) console.error(e);
      res.status(status).json({ error: status >= 500 ? 'Server error' : err.message });
    }
  };
}

export function fail(status: number, message: string): never {
  throw Object.assign(new Error(message), { status });
}
