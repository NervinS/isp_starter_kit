/**
 * E2E inventario (estable):
 * - Espera /v1/health y /v1/inventario/stock
 * - Descubre almacenes sin agregaciones sobre UUID
 * - Transferencia 10 p->t e idempotencia
 * - Verifica stock y desvíos (sin probar 409 aquí para no flakear)
 */

import request from 'supertest';
import { Pool } from 'pg';

jest.setTimeout(60_000);

const API = process.env.API || 'http://127.0.0.1:3000';
const TOKEN = process.env.TOKEN || 'devtoken';
const auth = { Authorization: `Bearer ${TOKEN}` };

const MAT_ONT = Number(process.env.MAT_ONT || 3);
const IDEMP = `e2e-${Date.now()}`;

const DB_URL = process.env.DB_URL;
const DB_HOST = process.env.DB_HOST || '127.0.0.1';
const DB_PORT = Number(process.env.DB_PORT || 5432);
const DB_USER = process.env.DB_USER || 'ispuser';
const DB_PASSWORD = process.env.DB_PASSWORD ?? '';
const DB_NAME = process.env.DB_NAME || 'ispdb';

const pool = DB_URL
  ? new Pool({ connectionString: DB_URL })
  : new Pool({
      host: DB_HOST,
      port: DB_PORT,
      user: DB_USER,
      password: DB_PASSWORD,
      database: DB_NAME,
    });

const q = async <T = any>(sql: string, params?: any[]) => {
  const c = await pool.connect();
  try {
    const r = await c.query(sql, params);
    return r.rows as T[];
  } finally {
    c.release();
  }
};

const waitHealth = async () => {
  const agent = request(API);
  for (let i = 0; i < 120; i++) {
    try {
      const r = await agent.get('/v1/health').timeout({ deadline: 2000 });
      if (r.status === 200) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error('API no respondió /v1/health a tiempo');
};

const waitStock = async () => {
  const agent = request(API);
  for (let i = 0; i < 120; i++) {
    try {
      const r = await agent
        .get('/v1/inventario/stock')
        .query({ scope: 'principal' })
        .set(auth)
        .timeout({ deadline: 2000 });
      if (r.status >= 200 && r.status < 500) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error('API no respondió /v1/inventario/stock?scope=principal a tiempo');
};

let ALM_PRI = '';
let ALM_TEC = '';

const getPair = async () => {
  type Row = { cantidad: string };
  const p = await q<Row>(
    `SELECT COALESCE((SELECT cantidad FROM stock_almacen WHERE almacen_id=$1 AND material_id=$2),0) AS cantidad`,
    [ALM_PRI, MAT_ONT],
  );
  const t = await q<Row>(
    `SELECT COALESCE((SELECT cantidad FROM stock_almacen WHERE almacen_id=$1 AND material_id=$2),0) AS cantidad`,
    [ALM_TEC, MAT_ONT],
  );
  return { P: Number(p[0]?.cantidad ?? 0), T: Number(t[0]?.cantidad ?? 0) };
};

describe('Inventario e2e', () => {
  beforeAll(async () => {
    await waitHealth();
    await waitStock();

    type A = { id: string };
    const pri = await q<A>(`SELECT id FROM almacenes WHERE tipo='principal' LIMIT 1;`);
    const tec = await q<A>(`SELECT id FROM almacenes WHERE tipo='tecnico'   LIMIT 1;`);
    if (!pri[0]?.id || !tec[0]?.id) {
      throw new Error('No se encontraron almacenes principal/tecnico');
    }
    ALM_PRI = pri[0].id;
    ALM_TEC = tec[0].id;
  });

  afterAll(async () => {
    await pool.end();
  });

  it('transferencia 10 p->t + idempotencia + desvío 0', async () => {
    const agent = request(API);

    const { P: P0, T: T0 } = await getPair();

    const body = {
      idempotencyKey: IDEMP,
      tipo: 'transferencia',
      almacenOrigenId: ALM_PRI,
      almacenDestinoId: ALM_TEC,
      materialIdInt: MAT_ONT,
      cantidad: 10,
    };

    const r1 = await agent.post('/v1/inventario/movimientos').set(auth).send(body);
    expect([200, 201]).toContain(r1.status);
    expect(r1.body).toHaveProperty('id');

    const { P: P1, T: T1 } = await getPair();
    expect(P1).toBe(P0 - 10);
    expect(T1).toBe(T0 + 10);

    // Idempotencia
    const r2 = await agent.post('/v1/inventario/movimientos').set(auth).send(body);
    expect([200, 201]).toContain(r2.status);
    expect(r2.body.id).toBe(r1.body.id);

    const { P: P2, T: T2 } = await getPair();
    expect(P2).toBe(P1);
    expect(T2).toBe(T1);

    // Desvíos 0
    const desv = await q<{ diff: string }>(
      `SELECT diff FROM v_desviacion_inv_tecnico WHERE material_id=$1 AND diff<>0`,
      [MAT_ONT],
    );
    expect(desv.length).toBe(0);
  });
});
