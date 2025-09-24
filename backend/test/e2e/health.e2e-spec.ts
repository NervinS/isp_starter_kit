import request from 'supertest';

const API_BASE = process.env.API_BASE || 'http://127.0.0.1:3000';

describe('Health (e2e)', () => {
  it('GET /v1/health -> ok:true', async () => {
    const res = await request(API_BASE).get('/v1/health');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('ok', true);
  });
});
