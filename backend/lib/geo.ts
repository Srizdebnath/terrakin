/** Great-circle distance in metres. */
export function metres(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const r = 6371008.8;
  const dLat = ((bLat - aLat) * Math.PI) / 180;
  const dLng = ((bLng - aLng) * Math.PI) / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos((aLat * Math.PI) / 180) * Math.cos((bLat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

/** Reads { lat, lng } from a request body, or fails with 400. */
export function latLng(body: unknown, fail: (status: number, msg: string) => never): { lat: number; lng: number } {
  const b = (body ?? {}) as { lat?: unknown; lng?: unknown };
  if (typeof b.lat !== 'number' || typeof b.lng !== 'number' || Math.abs(b.lat) > 85 || Math.abs(b.lng) > 180) {
    fail(400, 'lat and lng are required');
  }
  return { lat: b.lat as number, lng: b.lng as number };
}

/** Reads ?lat=&lng= from a query string, or fails with 400. */
export function latLngFromQuery(
  q: Record<string, string | string[] | undefined>,
  fail: (status: number, msg: string) => never,
): { lat: number; lng: number } {
  return latLng({ lat: Number(q.lat), lng: Number(q.lng) }, fail);
}
