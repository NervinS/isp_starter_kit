import { NextRequest, NextResponse } from 'next/server';

const BASE = (process.env.API_BASE_SSR || 'http://127.0.0.1:3000/v1').replace(/\/+$/, '');

export const runtime = 'nodejs'; // usa Node (no edge)

/**
 * Proxy: POST /api/ventas/:codigo/evidencias
 * Reenvía el multipart tal cual al backend Nest.
 */
export async function POST(
  req: NextRequest,
  { params }: { params: { codigo: string } }
) {
  try {
    const codigo = decodeURIComponent(params.codigo);

    // FormData entrante desde el navegador
    const incoming = await req.formData();

    // Creamos un nuevo FormData y copiamos con .forEach (sin iteradores)
    const fd = new FormData();
    incoming.forEach((value, key) => {
      // value puede ser string o File – se pasa tal cual
      fd.append(key, value as any);
    });

    // Reenvía al backend (NO fijes content-type; undici lo arma con el boundary)
    const be = await fetch(`${BASE}/ventas/${encodeURIComponent(codigo)}/evidencias`, {
      method: 'POST',
      body: fd,
    });

    const text = await be.text();
    if (!be.ok) {
      return NextResponse.json(
        { ok: false, err: text || `HTTP ${be.status}` },
        { status: be.status }
      );
    }

    // devolvemos tal cual (JSON)
    return new NextResponse(text, {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  } catch (err: any) {
    return NextResponse.json(
      { ok: false, err: err?.message || String(err) },
      { status: 500 }
    );
  }
}
