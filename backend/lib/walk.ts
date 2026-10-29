import { createHmac, timingSafeEqual } from 'node:crypto';
import { metres } from './geo.js';
import { derivedKey } from './secrets.js';

// Walk rewards (TerrakinStrides). While the app is open it asks for a stamp
// every ~100 m; each stamp is an HMAC over (wallet, spot, time), so it can't
// be forged or lent to another wallet. Claiming sends the stamps back: we add
// up the humanly paced stretches between them and sign the span that covers
// whole 500 m steps. Stamps after that span stay with the app for next time.

export interface WalkStamp {
  lat: number; // degrees × 1e5 (about 1 m)
  lng: number;
  t: number; // unix seconds
  mac: string;
}

export const STEP_M = 500; // TerrakinStrides.STEP
const MAX_MPS = 4.5; // a jog; faster stretches (bus, bike, car) don't count
const MAX_GAP_M = 400; // a jump this big is a GPS glitch or a skipped stretch
const MAX_SPAN_S = 3 * 60 * 60;
const FRESH_S = 10 * 60;

const mac = (wallet: string, lat: number, lng: number, t: number) =>
  createHmac('sha256', derivedKey('walk-stamps')).update(`${wallet.toLowerCase()}|${lat}|${lng}|${t}`).digest('base64url').slice(0, 22);

export function makeWalkStamp(wallet: string, lat: number, lng: number, t: number): WalkStamp {
  const la = Math.round(lat * 1e5), ln = Math.round(lng * 1e5);
  return { lat: la, lng: ln, t, mac: mac(wallet, la, ln, t) };
}

function stampOk(wallet: string, s: WalkStamp): boolean {
  if (!Number.isInteger(s?.lat) || !Number.isInteger(s?.lng) || !Number.isInteger(s?.t) || typeof s.mac !== 'string') return false;
  const want = new TextEncoder().encode(mac(wallet, s.lat, s.lng, s.t));
  const got = new TextEncoder().encode(s.mac);
  return want.length === got.length && timingSafeEqual(want, got);
}

export class WalkError extends Error {}

export interface Walk {
  from: number;
  to: number;
  metres: number;
  /** Index of the stamp the paid span ends at; the app keeps stamps from here on. */
  keepFrom: number;
}

/** Measures a walk and returns the span covering its whole 500 m steps. */
export function measureWalk(wallet: string, stamps: WalkStamp[], nowS: number): Walk {
  if (!Array.isArray(stamps) || stamps.length < 2 || stamps.length > 400) throw new WalkError('Keep walking: not enough of a walk yet');
  for (const s of stamps) if (!stampOk(wallet, s)) throw new WalkError('A walk stamp is invalid');
  const first = stamps[0], last = stamps[stamps.length - 1];
  if (nowS - last.t > FRESH_S) throw new WalkError('This walk is stale; keep the app open while you walk');
  if (last.t - first.t > MAX_SPAN_S) throw new WalkError('Claim at least every 3 hours of walking');

  // Running total of counted metres at each stamp.
  const total = [0];
  for (let i = 1; i < stamps.length; i++) {
    const a = stamps[i - 1], b = stamps[i];
    if (b.t <= a.t) throw new WalkError('Walk stamps are out of order');
    const d = metres(a.lat / 1e5, a.lng / 1e5, b.lat / 1e5, b.lng / 1e5);
    const counts = d <= MAX_GAP_M && d / (b.t - a.t) <= MAX_MPS;
    total.push(total[i - 1] + (counts ? d : 0));
  }
  const steps = Math.floor(total[total.length - 1] / STEP_M);
  if (steps === 0) throw new WalkError(`Walk ${STEP_M} m to earn MON`);
  const end = total.findIndex((m) => m >= steps * STEP_M);
  return { from: first.t, to: stamps[end].t, metres: Math.floor(total[end]), keepFrom: end };
}
