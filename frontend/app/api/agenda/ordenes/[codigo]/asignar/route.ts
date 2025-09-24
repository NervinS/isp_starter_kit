import { NextRequest, NextResponse } from 'next/server';

const BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://127.0.0.1:3000/v1';

export async function POST(_req: NextRequest, { params }: { params: { codigo: string } }) {
  const body = await _req.json();
  // Backend nuevo:
  // POST /v1/agenda/ordenes/:codigo/asignar  { fecha, turno, tecnicoCodigo|tecnico_codigo|tecnicoId }
  const url = `${BASE}/agenda/ordenes/${encodeURIComponent(params.codigo)}/asignar`;
  const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const txt = await r.text();
  return new NextResponse(txt, { status: r.status, headers: { 'content-type': r.headers.get('content-type') || 'application/json' } });
}
