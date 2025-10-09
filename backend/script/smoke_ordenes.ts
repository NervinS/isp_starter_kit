#!/usr/bin/env -S ts-node --transpile-only
/**
 * Smoke de órdenes (GET, evidencias, cerrar).
 *
 * Env vars:
 *  - API (default: http://localhost:3000/v1)
 *  - KEY (default: superdev)
 *  - COD (default: MAN-250929184104)
 *
 * Uso:
 *   API=http://localhost:3000/v1 KEY=superdev COD=MAN-250929184104 \
 *     ./script/smoke_ordenes.ts
 */

type Json = Record<string, any>;

const API = process.env.API ?? 'http://localhost:3000/v1';
const KEY = process.env.KEY ?? 'superdev';
const COD = process.env.COD ?? 'MAN-250929184104';

async function http<T = any>(
  method: 'GET' | 'POST' | 'PUT',
  path: string,
  body?: Json,
  extraHeaders?: Record<string, string>,
): Promise<{ status: number; data: T }> {
  const url = `${API}${path}`;
  const headers: Record<string, string> = {
    'x-api-key': KEY,
    ...(body ? { 'content-type': 'application/json' } : {}),
    ...(extraHeaders ?? {}),
  };
  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data: any;
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { _raw: text };
  }
  return { status: res.status, data };
}

function assert(cond: any, msg: string) {
  if (!cond) throw new Error(msg);
}

export async function runOrdenesSmoke(): Promise<void> {
  console.log('🧪 [ordenes] START', { API, COD });

  // 1) GET /ordenes/:codigo
  const r1 = await http('GET', `/ordenes/${encodeURIComponent(COD)}`);
  assert(r1.status === 200, `GET /ordenes/${COD} -> ${r1.status}`);
  assert(r1.data && (r1.data as any).codigo === COD, 'orden codigo mismatch');

  // 2) POST evidencias
  const evidenciasPayload = {
    firma_key: 'evidencias/ordenes/SMOKE/firma.png',
    foto1_key: 'evidencias/ordenes/SMOKE/foto1.jpg',
  };
  const r2 = await http('POST', `/ordenes/${encodeURIComponent(COD)}/evidencias`, evidenciasPayload);
  assert(r2.status === 201, `POST evidencias -> ${r2.status}`);
  assert((r2.data as any)?.ok === true, 'POST evidencias -> ok !== true');
  assert((r2.data as any)?.codigo === COD, 'POST evidencias -> codigo mismatch');
  assert((r2.data as any)?.firmaKey, 'POST evidencias -> firmaKey faltante');

  // 3) PUT cerrar (idempotente por header)
  const idemKey = `smoke-${COD}-${Date.now()}`;
  const cierrePayload = {
    comentarios: 'cierre smoke',
    materiales: [],
    equipos: { asignar: [], retirar: [] },
  };
  const r3 = await http(
    'PUT',
    `/ordenes/${encodeURIComponent(COD)}/cerrar`,
    cierrePayload,
    { 'Idempotency-Key': idemKey },
  );
  // Primer intento: 200 ok:true estado=cerrada; Reintento: 200 ok:true _idempotent:true
  assert(r3.status === 200, `PUT cerrar -> ${r3.status}`);
  assert((r3.data as any)?.ok === true, 'PUT cerrar -> ok !== true');

  if (!(r3.data as any)?._idempotent) {
    assert((r3.data as any)?.estado === 'cerrada', 'PUT cerrar -> estado !== cerrada');
    assert(!!(r3.data as any)?.cerradaAt, 'PUT cerrar -> cerradaAt faltante');
  }

  // 4) GET final para garantizar estado
  const r4 = await http('GET', `/ordenes/${encodeURIComponent(COD)}`);
  assert(r4.status === 200, `GET final -> ${r4.status}`);
  assert((r4.data as any)?.codigo === COD, 'GET final -> codigo mismatch');
  assert((r4.data as any)?.estado === 'cerrada', 'GET final -> estado !== cerrada');

  console.log('✅ [ordenes] OK');
}

// Ejecutar standalone
if (require.main === module) {
  runOrdenesSmoke()
    .then(() => {
      console.log('🚀 smoke_ordenes DONE');
      process.exit(0);
    })
    .catch((err) => {
      console.error('❌ smoke_ordenes FAILED');
      console.error(err);
      process.exit(1);
    });
}
