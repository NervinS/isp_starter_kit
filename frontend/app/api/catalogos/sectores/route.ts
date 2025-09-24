import { NextRequest, NextResponse } from 'next/server';
const BASE = process.env.API_BASE_SSR || 'http://127.0.0.1:3000/v1';

export async function GET(req: NextRequest) {
  const u = new URL(req.url);
  const municipio = u.searchParams.get('municipio') ?? '';
  const zona = u.searchParams.get('zona') ?? '';
  const r = await fetch(`${BASE}/catalogos/sectores?municipio=${encodeURIComponent(municipio)}&zona=${encodeURIComponent(zona)}`, { cache: 'no-store' });
  const t = await r.text();
  return new NextResponse(t, { status: r.status, headers: { 'content-type': r.headers.get('content-type') ?? 'application/json; charset=utf-8' } });
}
