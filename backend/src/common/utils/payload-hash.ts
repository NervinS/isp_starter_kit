import crypto from 'crypto';

/**
 * Canonicaliza un objeto JSON:
 * - ordena claves recursivamente
 * - trimea strings
 * - coacciona undefined -> null
 */
export function canonicalize(obj: any): any {
  if (obj === null || obj === undefined) return null;
  if (Array.isArray(obj)) return obj.map(canonicalize);
  if (typeof obj === 'object') {
    const sorted = Object.keys(obj).sort();
    const out: any = {};
    for (const k of sorted) {
      const v = obj[k];
      out[k] = canonicalize(v);
    }
    return out;
  }
  if (typeof obj === 'string') return obj.trim();
  return obj;
}

export function sha256(data: string): string {
  return crypto.createHash('sha256').update(data).digest('hex');
}

/** hash estable del payload normalizado */
export function payloadHash(payload: any): string {
  const norm = canonicalize(payload);
  const txt = JSON.stringify(norm);
  return sha256(txt);
}
