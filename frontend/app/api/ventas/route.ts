import { NextRequest, NextResponse } from 'next/server';

const API_BASE = process.env.API_BASE_SSR!;

async function getVenJwt() {
  if (process.env.SERVER_VEN_JWT || process.env.VENTAS_TOKEN) {
    return process.env.SERVER_VEN_JWT || process.env.VENTAS_TOKEN!;
  }
  const u = process.env.VEN_USER || 'ven1';
  const p = process.env.VEN_PASS || 'Ven123!';
  const res = await fetch(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username: u, password: p }),
  });
  if (!res.ok) throw new Error(`login ventas falló (${res.status})`);
  const { access_token } = await res.json();
  return access_token as string;
}

export async function GET(req: NextRequest) {
  try {
    if (!API_BASE) throw new Error('API_BASE_SSR no configurado');
    const jwt = await getVenJwt();

    const { searchParams } = new URL(req.url);
    const url = new URL(`${API_BASE}/ventas`);
    const estado = searchParams.get('estado');
    if (estado) url.searchParams.set('estado', estado);

    const be = await fetch(url.toString(), {
      headers: { Authorization: `Bearer ${jwt}` },
      cache: 'no-store',
    });
    const text = await be.text();
    const type = be.headers.get('content-type') || 'application/json; charset=utf-8';
    return new NextResponse(text, { status: be.status, headers: { 'content-type': type } });
  } catch (err: any) {
    return NextResponse.json({ ok: false, err: err?.message ?? String(err) }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    if (!API_BASE) throw new Error('API_BASE_SSR no configurado');
    const jwt = await getVenJwt();
    const body = await req.json();

    const be = await fetch(`${API_BASE}/ventas`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        Authorization: `Bearer ${jwt}`,
      },
      body: JSON.stringify(body),
      cache: 'no-store',
    });

    const text = await be.text();
    const type = be.headers.get('content-type') || 'application/json; charset=utf-8';
    return new NextResponse(text, { status: be.status, headers: { 'content-type': type } });
  } catch (err: any) {
    return NextResponse.json({ ok: false, err: err?.message ?? String(err) }, { status: 500 });
  }
}
