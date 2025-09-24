import request from 'supertest';

const API_BASE = process.env.API_BASE ?? '';

const maybe = (cond: boolean) => (cond ? describe : describe.skip);

maybe(!!API_BASE)('Health E2E (remote API)', () => {
  it('/v1/health -> { ok: true }', async () => {
    const res = await request(API_BASE).get('/v1/health');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('ok', true);
    expect(typeof res.body.ts).toBe('string');
  });
});
