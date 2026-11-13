// lib/randomId.ts — one UUID helper for the whole app.
// Uses the platform crypto.randomUUID() when present (Node, Deno, modern
// React Native/Hermes); falls back to an RFC 4122 v4 built from
// Math.random so the app never crashes on an older runtime.
// The fallback is NOT cryptographic — it is only used for anonymous
// user ids and idempotency keys, never for secrets.

export function randomId(): string {
  const g = globalThis as {
    crypto?: { randomUUID?: () => string };
  };
  if (typeof g.crypto?.randomUUID === 'function') {
    return g.crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
