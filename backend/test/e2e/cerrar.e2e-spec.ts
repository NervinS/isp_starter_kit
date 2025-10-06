import request from 'supertest';

const API_BASE = process.env.API_BASE ?? '';
const API_KEY  = process.env.API_KEY  ?? 'superdev';
const maybe = (cond: boolean) => (cond ? describe : describe.skip);

type Orden = { id?: string; codigo: string; estado?: string };
type OrdenItem = { id?: string; codigo: string; estado?: string };

const get  = (path: string) => request(API_BASE).get(path).set('x-api-key', API_KEY);
const put  = (path: string) => request(API_BASE).put(path).set('x-api-key', API_KEY);

maybe(!!API_BASE)('Ordenes cierre (E2E contra API real)', () => {
  let codigo: string;

  beforeAll(async () => {
    const r = await get(`/ordenes?limit=1`);
    expect(r.status).toBe(200);

    // Soporta [] o { items: [] }
    const body = r.body;
    const ordenes: OrdenItem[] = Array.isArray(body) ? body : (Array.isArray(body?.items) ? body.items : []);
    expect(Array.isArray(ordenes)).toBe(true);
    expect(ordenes.length).toBeGreaterThan(0);

    codigo = ordenes[0].codigo;
  });

  it('cierra idempotente (dos llamadas deben responder 200)', async () => {
    const r1 = await put(`/ordenes/${codigo}/cerrar`);
    expect(r1.status).toBe(200);

    // Acepta { ok:true } o { codigo, estado:'cerrada', ... }
    const ok1 = r1.body?.ok === true || r1.body?.estado === 'cerrada';
    expect(ok1).toBe(true);

    const id1 = r1.body?.id as string | undefined;
    const cod1 = r1.body?.codigo as string | undefined;

    const r2 = await put(`/ordenes/${codigo}/cerrar`);
    expect(r2.status).toBe(200);

    const ok2 = r2.body?.ok === true || r2.body?.estado === 'cerrada';
    expect(ok2).toBe(true);

    const id2 = r2.body?.id as string | undefined;
    const cod2 = r2.body?.codigo as string | undefined;

    // Si vienen, deben coincidir
    if (id1 && id2) expect(id2).toBe(id1);
    if (cod1 && cod2) expect(cod2).toBe(cod1);

    // Si trae estado, debe ser 'cerrada'
    if (r2.body?.estado) expect(r2.body.estado).toBe('cerrada');
  });
});
