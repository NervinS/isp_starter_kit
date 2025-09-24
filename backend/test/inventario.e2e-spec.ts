import request from 'supertest';

const API_BASE = process.env.API_BASE ?? '';
const maybe = (cond: boolean) => (cond ? describe : describe.skip);

type Tecnico = { id: string; codigo: string; nombre: string };
type Material = { id: number; codigo: string; nombre: string };

maybe(!!API_BASE)('Inventario E2E (contra API real)', () => {
  let TECID: string;
  let MATID: number;

  beforeAll(async () => {
    // Resolver TEC-0001
    const tec = await request(API_BASE).get('/v1/tecnicos');
    expect(tec.status).toBe(200);
    const tecnicos: Tecnico[] = tec.body ?? [];
    const t = tecnicos.find((x) => x.codigo === 'TEC-0001') ?? tecnicos[0];
    expect(t).toBeTruthy();
    TECID = t.id;

    // Resolver MAT-0001
    const mat = await request(API_BASE).get('/v1/materiales');
    expect(mat.status).toBe(200);
    const materiales: Material[] = mat.body ?? [];
    const m = materiales.find((x) => x.codigo === 'MAT-0001') ?? materiales[0];
    expect(m).toBeTruthy();
    MATID = m.id;
  });

  it('GET /v1/inventario/tecnicos/:id/stock -> 200 y array', async () => {
    const res = await request(API_BASE).get(`/v1/inventario/tecnicos/${TECID}/stock`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  it('POST /agregar-stock -> 2xx y ok:true', async () => {
    const res = await request(API_BASE)
      .post(`/v1/inventario/tecnicos/${TECID}/agregar-stock`)
      .send({ materialId: MATID, cantidad: 1 });
    expect([200, 201]).toContain(res.status);
    expect(res.body).toHaveProperty('ok', true);
  });

  it('POST /descontar-stock exagerado -> 400', async () => {
    const res = await request(API_BASE)
      .post(`/v1/inventario/tecnicos/${TECID}/descontar-stock`)
      .send({ materialId: MATID, cantidad: 999999 });
    expect(res.status).toBe(400);
    // mensaje claro (si viene)
    if (res.body?.message) {
      expect(typeof res.body.message).toBe('string');
    }
  });
});
