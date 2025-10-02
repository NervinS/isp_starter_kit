import request from 'supertest';

const API_BASE = process.env.API_BASE ?? 'http://127.0.0.1:3000/v1';

type Tecnico = { id: string; codigo: string; nombre: string };
type Material = { id: number; codigo: string; nombre: string };

describe('Inventario E2E (API real)', () => {
  let TECID: string;
  let MATID: number;

  beforeAll(async () => {
    // Tecnicos (tomamos el primero si no está TEC-0001)
    const tec = await request(API_BASE).get('/tecnicos');
    expect(tec.status).toBe(200);
    const tecnicos: Tecnico[] = tec.body ?? [];
    const t = tecnicos.find((x) => x.codigo === 'TEC-0001') ?? tecnicos[0];
    expect(t).toBeTruthy();
    TECID = t.id;

    // Materiales (tomamos el primero si no está MAT-0001)
    const mat = await request(API_BASE).get('/materiales');
    expect(mat.status).toBe(200);
    const materiales: Material[] = mat.body ?? [];
    const m = materiales.find((x) => x.codigo === 'MAT-0001') ?? materiales[0];
    expect(m).toBeTruthy();
    MATID = m.id;
  });

  it('GET stock técnico -> 200 y array', async () => {
    const res = await request(API_BASE).get(`/inventario/tecnicos/${TECID}/stock`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  it('flujo feliz: ingreso 5 -> egreso 3 -> ajuste set=2 (todo ok:true)', async () => {
    const r1 = await request(API_BASE)
      .post(`/inventario/tecnicos/${TECID}/agregar`)
      .send({ materialId: MATID, cantidad: 5, nota: 'e2e ingreso' });
    expect([200, 201]).toContain(r1.status);
    expect(r1.body).toHaveProperty('ok', true);

    const r2 = await request(API_BASE)
      .post(`/inventario/tecnicos/${TECID}/descontar`)
      .send({ materialId: MATID, cantidad: 3, nota: 'e2e egreso' });
    expect([200, 201]).toContain(r2.status);
    expect(r2.body).toHaveProperty('ok', true);

    const r3 = await request(API_BASE)
      .post(`/inventario/tecnicos/${TECID}/ajustar`)
      .send({ materialId: MATID, cantidad: 2, nota: 'e2e set=2' });
    expect([200, 201]).toContain(r3.status);
    expect(r3.body).toHaveProperty('ok', true);
  });

  it('negativo: egreso sin stock suficiente -> 409 saldo insuficiente', async () => {
    const res = await request(API_BASE)
      .post(`/inventario/tecnicos/${TECID}/descontar`)
      .send({ materialId: MATID, cantidad: 999999, nota: 'forzar 409' });
    expect(res.status).toBe(409);
    expect(res.body?.message ?? '').toMatch(/saldo insuficiente/i);
  });
});

