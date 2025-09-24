import { NextRequest, NextResponse } from 'next/server';

const API_BASE = process.env.API_BASE_SSR || 'http://127.0.0.1:3000/v1';
const VEN_USER = process.env.VEN_USER || 'ven1';
const VEN_PASS = process.env.VEN_PASS || 'Ven123!';

let cachedToken: string | null = null;
let tokenExp: number = 0;

async function loginVentas(): Promise<string> {
  const now = Date.now();
  if (cachedToken && tokenExp > now + 15_000) return cachedToken;

  const r = await fetch(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username: VEN_USER, password: VEN_PASS })
  });

  if (!r.ok) {
    const t = await r.text();
    throw new Error(`login ventas falló (${r.status}) ${t}`);
  }
  const j = await r.json();
  cachedToken = j?.access_token || null;
  // exp en segundos -> ms; si no viene, 20 minutos
  const expSec = (j?.exp as number) || Math.floor(Date.now() / 1000) + 20 * 60;
  tokenExp = expSec * 1000;
  if (!cachedToken) throw new Error('login ventas sin token');
  return cachedToken;
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({}));

    const codigo: string | undefined = body?.codigo;
    if (!codigo) {
      return NextResponse.json({ ok: false, err: 'Falta "codigo"' }, { status: 400 });
    }

    // MUY IMPORTANTE: re-enviar TODO el payload (incluidas las base64)
    const payload = {
      codigo,
      firma_base64: body?.firma_base64 ?? null,
      recibo_base64: body?.recibo_base64 ?? null,
      cedula_base64: body?.cedula_base64 ?? null,
    };

    const token = await loginVentas();
    const r = await fetch(`${API_BASE}/ventas/${encodeURIComponent(codigo)}/pagar`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(payload),
    });

    const text = await r.text();
    if (!r.ok) {
      return NextResponse.json(
        { ok: false, err: `HTTP ${r.status}`, detail: text },
        { status: r.status }
      );
    }
    // Devuelve { ok, venta: {recibo_url, contrato_url, ...}, orden: {...} }
    return new NextResponse(text, {
      status: 200,
      headers: { 'content-type': 'application/json; charset=utf-8' },
    });
  } catch (e: any) {
    return NextResponse.json({ ok: false, err: e?.message || String(e) }, { status: 500 });
  }
}
