import { NextResponse } from 'next/server';

const API_BASE_SSR = process.env.API_BASE_SSR || 'http://127.0.0.1:3000/v1';

async function fetchUpstream(path: string, params: Record<string, string | undefined>) {
  const url = new URL(`${API_BASE_SSR}${path}`);
  for (const [k, v] of Object.entries(params)) {
    if (v != null && v !== '') url.searchParams.set(k, v);
  }
  const r = await fetch(url.toString(), { cache: 'no-store' });
  if (!r.ok) {
    const t = await r.text();
    throw new Error(`Upstream ${r.status}: ${t.slice(0, 500)}`);
  }
  return r.json();
}

export async function GET(req: Request) {
  try {
    const { searchParams } = new URL(req.url);
    const estado = searchParams.get('estado') || '';
    const codigo = searchParams.get('codigo') || '';
    const q = searchParams.get('q') || '';

    // Si piden por código, devolvemos lo que traiga el backend
    if (codigo) {
      const data = await fetchUpstream('/ordenes', { codigo });
      return NextResponse.json(data, { status: 200 });
    }

    // "pendientes" = creadas + agendadas (combinadas)
    if (estado === 'pendientes') {
      const [creadas, agendadas] = await Promise.all([
        fetchUpstream('/ordenes', { estado: 'creada', q }),
        fetchUpstream('/ordenes', { estado: 'agendada', q }),
      ]);
      const merged = [...(creadas || []), ...(agendadas || [])];
      return NextResponse.json(merged, { status: 200 });
    }

    // Cualquier otro estado pasa directo al backend
    const data = await fetchUpstream('/ordenes', { estado, q });
    return NextResponse.json(data, { status: 200 });
  } catch (err: any) {
    return NextResponse.json(
      { ok: false, error: 'Frontend /api/ordenes failed', detail: err?.message || String(err) },
      { status: 500 },
    );
  }
}

