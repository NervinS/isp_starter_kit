import { NextRequest, NextResponse } from 'next/server';

const API_BASE = process.env.API_BASE_SSR || 'http://127.0.0.1:3000/v1';

export async function POST(req: NextRequest, { params }: { params: { codigo: string } }) {
  const codigo = params.codigo;
  const body = await req.json(); // { fecha, turno, tecnicoCodigo? | tecnicoId? }

  const r = await fetch(`${API_BASE}/agenda/ordenes/${encodeURIComponent(codigo)}/reagendar`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    // importante: sin credenciales, porque es SSR → backend
  });

  const text = await r.text();
  try {
    const json = text ? JSON.parse(text) : null;
    if (!r.ok) return NextResponse.json(json || { error: text || 'Error' }, { status: r.status });
    return NextResponse.json(json ?? { ok: true });
  } catch {
    if (!r.ok) return NextResponse.json({ error: text }, { status: r.status });
    return NextResponse.json({ ok: true, raw: text });
  }
}
