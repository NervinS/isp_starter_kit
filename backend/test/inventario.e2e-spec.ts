import request from 'supertest';

const API_BASE = process.env.API_BASE ?? '';
const API_KEY  = process.env.API_KEY  ?? 'superdev';
const TECID_ENV = process.env.TECID ?? '6'; // <- usa tu técnico conocido
const maybe = (cond: boolean) => (cond ? describe : describe.skip);

type Material = { id: number; codigo: string; nombre: string };

const get  = (path: string) => request(API_BASE).get(path).set('x-api-key', API_KEY);
const post = (path: string) => request(API_BASE).post(path).set('x-api-key', API_KEY);

maybe(!!API_BASE)('Inventario E2E (API real)', () => {
  let TECID: string = TECID_ENV;
  let MATID: number = 1;

  beforeAll(async () => {
    // Materiales (tomamos MAT-0001 si existe, sino el primero, sino fallback 1)
    const mat = await get('/materiales');
    expect(mat.status).toBe(200);
    const materiales: Material[] = Array.isArray(mat.body) ? mat.body : [];
    if (materiales.length > 0) {
      const m = materiales.find((x) => x.codigo === 'MAT-0001') ?? materiales[0];
      MATID = m.id;
    }
  });

  it('GET stock técnico -> 200 y array', async () => {
    const res = await get(`/inventario/tecnicos/${TECID}/stock`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  it('flujo feliz: ingreso 5 -> egreso 3 -> ajuste set=2 (todo ok:true)', async () => {
    const r1 = await post(`/inventario/tecnicos/${TECID}/agregar`).send({ materialId: MATID, cantidad: 5, nota: 'e2e ingreso' });
    expect([200, 201]).toContain(r1.status);
    expect(r1.body).toHaveProperty('ok', true);

    const r2 = await post(`/inventario/tecnicos/${TECID}/descontar`).send({ materialId: MATID, cantidad: 3, nota: 'e2e egreso' });
    expect([200, 201]).toContain(r2.status);
    expect(r2.body).toHaveProperty('ok', true);

    const r3 = await post(`/inventario/tecnicos/${TECID}/ajustar`).send({ materialId: MATID, cantidad: 2, nota: 'e2e set=2' });
    expect([200, 201]).toContain(r3.status);
    expect(r3.body).toHaveProperty('ok', true);
  });

  it('negativo: egreso sin stock suficiente -> 409 saldo insuficiente', async () => {
    const r = await post(`/inventario/tecnicos/${TECID}/descontar`).send({ materialId: MATID, cantidad: 999999, nota: 'forzar 409' });
    expect(r.status).toBe(409);
    expect((r.body?.message ?? '').toLowerCase()).toContain('saldo insuficiente');
  });
});
