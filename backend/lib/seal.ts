import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { derivedKey } from './secrets.js';

// Dead drop spots go on-chain sealed: AES-256-GCM over the micro-degree
// coordinates, so only this backend can tell how close a claimer stands.

const u8 = (b: ArrayBufferView) => new Uint8Array(b.buffer, b.byteOffset, b.byteLength);

/** 36 bytes: iv (12) | ciphertext (8) | tag (16). */
export function seal(latE6: number, lngE6: number): Uint8Array {
  const iv = u8(randomBytes(12));
  const c = createCipheriv('aes-256-gcm', derivedKey('drop-spots'), iv);
  const pt = new Uint8Array(8);
  const v = new DataView(pt.buffer);
  v.setInt32(0, latE6);
  v.setInt32(4, lngE6);
  const out = new Uint8Array(36);
  out.set(iv, 0);
  out.set(u8(c.update(pt)), 12);
  c.final();
  out.set(u8(c.getAuthTag()), 20);
  return out;
}

export function unseal(blob: Uint8Array): { lat: number; lng: number } {
  if (blob.length !== 36) throw new Error('Bad sealed spot');
  const d = createDecipheriv('aes-256-gcm', derivedKey('drop-spots'), blob.subarray(0, 12));
  d.setAuthTag(blob.subarray(20));
  const pt = u8(d.update(blob.subarray(12, 20)));
  d.final();
  const v = new DataView(pt.buffer, pt.byteOffset, 8);
  return { lat: v.getInt32(0) / 1e6, lng: v.getInt32(4) / 1e6 };
}
