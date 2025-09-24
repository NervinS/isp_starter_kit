import { NextResponse } from 'next/server';

const API_BASE_SSR = process.env.API_BASE_SSR || 'http://127.0.0.1:3000/v1';

export async function GET(req: Request) {
  try {
    const { searchParams } = new URL(req.url);
    const estado = searchParams.get('estado') ?? '';      // "creada" | "agendada" | "" (todas)
    const q = searchParams.get('q') ?? '';                // búsqueda libre (código, nombre, doc)

    // Construye URL al backend Nest (ABSOLUTA)
    const url = new URL(`${API_BASE_SSR}/ordenes`);
    if (estado) url.searchParams.set('estado', estado);
    if (q) url.searchParams.set('q', q);

    const upstream = await fetch(url.toString(), { cache: 'no-store' });
    if (!upstream.ok) {
      const text = await upstream.text();
      return NextResponse.json(
        { ok: false, error: `Upstream ${upstream.status}`, detail: text.slice(0, 500) },
        { status: upstream.status }
      );
    }
    const data = await upstream.json();
    return NextResponse.json(data, { status: 200 });
  } catch (err: any) {
    return NextResponse.json(
      { ok: false, error: 'Agenda API handler failed', detail: err?.message || String(err) },
      { status: 500 }
    );
  }
}
