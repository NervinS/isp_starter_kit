// app/api/usuarios/route.ts
import { NextResponse } from 'next/server';

const API_BASE =
  process.env.API_BASE_SSR ||
  process.env.NEXT_PUBLIC_API_BASE ||
  'http://127.0.0.1:3000/v1';

function buildTarget(path: string, reqUrl: string) {
  const src = new URL(reqUrl);
  const dst = new URL(path, API_BASE);
  src.searchParams.forEach((v, k) => dst.searchParams.set(k, v));
  return dst;
}

export async function GET(req: Request) {
  try {
    const target = buildTarget('/usuarios', req.url);
    const res = await fetch(target.toString(), {
      next: { revalidate: 0 },
      headers: { 'Content-Type': 'application/json' },
    });
    const text = await res.text();
    return new NextResponse(text, {
      status: res.status,
      headers: { 'Content-Type': res.headers.get('Content-Type') || 'application/json' },
    });
  } catch (err: any) {
    return NextResponse.json(
      { message: err?.message || 'Upstream error (/usuarios)' },
      { status: 500 }
    );
  }
}
