import { NextResponse } from 'next/server';
const BASE = process.env.API_BASE_SSR || 'http://127.0.0.1:3000/v1';
export async function GET() {
  const r = await fetch(`${BASE}/catalogos/vias`, { cache: 'no-store' });
  const t = await r.text();
  return new NextResponse(t, { status: r.status, headers: { 'content-type': r.headers.get('content-type') ?? 'application/json; charset=utf-8' } });
}
