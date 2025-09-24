import { NextResponse } from 'next/server';

const BASE =
  process.env.API_BASE_SSR && process.env.API_BASE_SSR.startsWith('http')
    ? process.env.API_BASE_SSR
    : 'http://127.0.0.1:3000/v1';

export async function GET() {
  try {
    const r = await fetch(`${BASE}/health`, { cache: 'no-store' });
    const text = await r.text();
    return new Response(text, {
      status: r.status,
      headers: { 'content-type': r.headers.get('content-type') ?? 'application/json' },
    });
  } catch (e: any) {
    return NextResponse.json({ ok: false, err: e?.message || 'Failed to fetch' }, { status: 502 });
  }
}
