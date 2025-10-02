import request from 'supertest';

const API_BASE = process.env.API_BASE ?? 'http://127.0.0.1:3000/v1';

type Orden = { id: string; codigo: string; estado: string };

describe('Ordenes cierre (E2E contra API real)', () => {
  let codigo: string;

  beforeAll(async () => {
    // Tomamos una orden cualquiera de la lista /v1/ordenes
    const r = await request(API_BASE).get(`/ordenes?limit=1`);
    expect(r.status).toBe(200);
    const ordenes: Orden[] = r.body ?? [];
    expect(Array.isArray(ordenes)).toBe(true);
    expect(ordenes.length).toBeGreaterThan(0);
    codigo = ordenes[0].codigo;
  });

  it('cierra idempotente (dos llamadas deben responder 200)', async () => {
    const r1 = await request(API_BASE).post(`/ordenes/${codigo}/cerrar-completo`);
    expect(r1.status).toBe(200);

    const r2 = await request(API_BASE).post(`/ordenes/${codigo}/cerrar-completo`);
    expect(r2.status).toBe(200);
  });
});
