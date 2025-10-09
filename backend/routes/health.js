const express = require('express');
const { Pool } = require('pg');
const router = express.Router();

let _pool;
function getPool() {
  if (_pool) return _pool;
  const conn =
    process.env.DATABASE_URL ||
    `postgres://${process.env.PGUSER || 'ispuser'}:${process.env.PGPASSWORD || ''}@${process.env.PGHOST || 'db'}:${process.env.PGPORT || '5432'}/${process.env.PGDATABASE || 'ispdb'}`;
  _pool = new Pool({ connectionString: conn, max: 5 });
  return _pool;
}

const API_KEY = process.env.API_KEY || 'superdev';
router.use((req, res, next) => {
  if (req.header('x-api-key') !== API_KEY) return res.status(401).json({ error: 'unauthorized' });
  next();
});

router.get('/inventario', async (_req, res) => {
  try {
    const pool = getPool();
    const { rows: [{ diffs }] } = await pool.query('SELECT public.fn_stock_diff_count() AS diffs');
    res.json({ ok: Number(diffs) === 0, diffs: Number(diffs) });
  } catch (err) {
    console.error('health inventario:', err);
    res.status(500).json({ ok: false, error: 'db_error' });
  }
});

router.get('/inventario/diffs', async (_req, res) => {
  try {
    const pool = getPool();
    const { rows } = await pool.query(`
      SELECT almacen, material, real, teorica, delta
      FROM public.v_stock_consistencia
      WHERE delta <> 0
      ORDER BY ABS(delta) DESC
      LIMIT 100
    `);
    res.json(rows);
  } catch (err) {
    console.error('diffs inventario:', err);
    res.status(500).json({ error: 'db_error' });
  }
});

router.post('/inventario/rebuild', async (_req, res) => {
  try {
    const pool = getPool();
    await pool.query('SELECT public.fn_stock_rebuild()');
    const { rows: [{ diffs }] } = await pool.query('SELECT public.fn_stock_diff_count() AS diffs');
    res.json({ ok: Number(diffs) === 0, diffs: Number(diffs) });
  } catch (err) {
    console.error('rebuild inventario:', err);
    res.status(500).json({ ok: false, error: 'db_error' });
  }
});

module.exports = router;
