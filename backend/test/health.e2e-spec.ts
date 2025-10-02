import request from 'supertest';

const API_BASE = process.env.API_BASE ?? 'http://127.0.0.1:3000/v1';

describe('Health E2E (remote API)', () => {
  it('/health -> { ok: true }', async () => {
    const res = await request(API_BASE).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('ok', true);
    expect(typeof res.body.ts).toBe('string');
  });
});
