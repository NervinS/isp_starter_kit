import { NextRequest, NextResponse } from 'next/server';

// Base del backend
const BASE =
  process.env.API_BASE_SSR && process.env.API_BASE_SSR.startsWith('http')
    ? process.env.API_BASE_SSR
    : 'http://127.0.0.1:3000/v1';

// Credenciales de técnico desde .env.local
const TEC_USER = process.env.TEC_USER || '';
const TEC_PASS = process.env.TEC_PASS || '';

// Cache simple del JWT en memoria del proceso de Next
let tecToken: { token: string; exp: number } | null = null;

async function loginTecnico(): Promise<string> {
  // reutiliza si faltan >60s para expirar
  const now = Math.floor(Date.now() / 1000);
  if (tecToken && tecToken.exp - now > 60) return tecToken.token;

  const url = `${BASE}/auth/login`;
  const r = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username: TEC_USER, password: TEC_PASS }),
    cache: 'no-store',
  });

  const text = await r.text();
  if (!r.ok) {
    return Promise.reject(
      new Error(`login tec falló (${r.status}) ${text}`)
    );
  }

  const j = JSON.parse(text);
  const token = j?.access_token as string;
  if (!token) throw new Error('login tec: no access_token');

  // decodifica solo el payload para leer exp
  const payload = JSON.parse(
    Buffer.from(token.split('.')[1] || '', 'base64').toString('utf8')
  );
  const exp = Number(payload?.exp || 0);

  tecToken = { token, exp };
  return token;
}

export async function GET(_req: NextRequest) {
  try {
    // sanity check del backend
    const h = await fetch(`${BASE}/health`, { cache: 'no-store' });
    if (!h.ok) {
      const ht = await h.text();
      return NextResponse.json(
        { ok: false, err: `backend health ${h.status}: ${ht}` },
        { status: 502 },
      );
    }

    const token = await loginTecnico();

    const r = await fetch(`${BASE}/planes`, {
      headers: { Authorization: `Bearer ${token}` },
      cache: 'no-store',
    });

    const text = await r.text();
    const type = r.headers.get('content-type') || 'application/json; charset=utf-8';
    return new NextResponse(text, {
      status: r.status,
      headers: { 'content-type': type, 'x-proxy-auth': 'tec', 'x-proxy-base': BASE },
    });
  } catch (err: any) {
    return NextResponse.json(
      { ok: false, err: err?.message || String(err) },
      { status: 500 },
    );
  }
}
