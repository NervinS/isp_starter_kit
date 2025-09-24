import request from 'supertest';

const API_BASE = process.env.API_BASE ?? '';
const maybe = (cond: boolean) => (cond ? describe : describe.skip);

maybe(!!API_BASE)('Ordenes cierre (E2E contra API real)', () => {
  const OID = process.env.E2E_ORD_CODIGO || 'ORD-SEED-1003';

  it('cierra idempotente (dos POST -> misma orden, estado cerrada)', async () => {
    const r1 = await request(API_BASE).post(`/v1/ordenes/${OID}/cerrar-completo`);
    expect(r1.status).toBe(200);
    expect(r1.body).toHaveProperty('ok', true);
    expect(r1.body).toHaveProperty('estado', 'cerrada');
    const id1 = r1.body.id;

    const r2 = await request(API_BASE).post(`/v1/ordenes/${OID}/cerrar-completo`);
    expect(r2.status).toBe(200);
    expect(r2.body).toHaveProperty('ok', true);
    expect(r2.body).toHaveProperty('estado', 'cerrada');
    expect(r2.body.id).toBe(id1);
  });
});
