import { NextRequest, NextResponse } from 'next/server';

const API_BASE =
  process.env.API_BASE_SSR && process.env.API_BASE_SSR.startsWith('http')
    ? process.env.API_BASE_SSR
    : 'http://127.0.0.1:3000/v1';

let TEC_JWT_CACHE: string | null = null;
let TEC_JWT_TS = 0;

async function loginTecnico(): Promise<string> {
  const username = process.env.TEC_USER || 'tec1';
  const password = process.env.TEC_PASS || 'Tec123!';
  const r = await fetch(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  if (!r.ok) {
    const msg = await r.text().catch(() => '');
    throw new Error(`login técnico falló (${r.status}) ${msg}`);
  }
  const data = await r.json();
  const token: string | undefined = data?.access_token;
  if (!token) throw new Error('login técnico no devolvió access_token');
  return token;
}

async function getTecJwt(): Promise<string> {
  const envToken = process.env.SERVER_TEC_JWT || process.env.API_TECH_TOKEN;
  if (envToken && envToken.trim()) return envToken.trim();

  const now = Date.now();
  if (TEC_JWT_CACHE && now - TEC_JWT_TS < 10 * 60 * 1000) return TEC_JWT_CACHE;

  const jwt = await loginTecnico();
  TEC_JWT_CACHE = jwt;
  TEC_JWT_TS = now;
  return jwt;
}

async function fetchWithTecAuth(input: string, init: RequestInit & { body?: any }) {
  let jwt = await getTecJwt();
  let res = await fetch(input, {
    ...init,
    headers: {
      ...(init.headers || {}),
      Authorization: `Bearer ${jwt}`,
    },
  });

  if (res.status === 401) {
    TEC_JWT_CACHE = null;
    jwt = await getTecJwt();
    res = await fetch(input, {
      ...init,
      headers: {
        ...(init.headers || {}),
        Authorization: `Bearer ${jwt}`,
      },
    });
  }
  return res;
}

export async function POST(
  req: NextRequest,
  { params }: { params: { codigo: string } },
) {
  try {
    const codigo = params?.codigo;
    if (!codigo) {
      return NextResponse.json(
        { ok: false, err: 'Código requerido' },
        { status: 400 },
      );
    }

    // Content-Type original (con boundary si es multipart)
    const contentType = req.headers.get('content-type') || undefined;

    // Lee TODO a Buffer (evita problemas de streaming)
    const ab = await req.arrayBuffer();
    const buf = Buffer.from(ab);
    if (!buf.length) {
      return NextResponse.json(
        { ok: false, err: 'Body vacío en proxy' },
        { status: 400 },
      );
    }

    const be = await fetchWithTecAuth(
      `${API_BASE}/ordenes/${encodeURIComponent(codigo)}/cerrar-completo`,
      {
        method: 'POST',
        body: buf,
        cache: 'no-store',
        headers: {
          ...(contentType ? { 'content-type': contentType } : {}),
        },
      },
    );

    const text = await be.text();
    const type =
      be.headers.get('content-type') || 'application/json; charset=utf-8';
    return new NextResponse(text, {
      status: be.status,
      headers: { 'content-type': type, 'x-proxy-auth': 'tec' },
    });
  } catch (err: any) {
    return NextResponse.json(
      { ok: false, err: err?.message ?? String(err) },
      { status: 500 },
    );
  }
}
