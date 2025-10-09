import { Router, Request, Response } from "express";
import { Pool } from "pg";

const router = Router();
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

router.get("/v1/inventario/kardex", async (req: Request, res: Response) => {
  try {
    const limit = Math.min(Number(req.query.limit ?? 100), 500);
    const { rows } = await pool.query(
      `SELECT id, tipo, material_id, cantidad, tecnico_id, nota, idempotency_key, delta, created_at AS fecha
         FROM public.movimientos
         ORDER BY created_at DESC
         LIMIT $1`, [limit]
    );
    res.json(rows.map(r => ({
      id: String(r.id),
      tipo: r.tipo,
      materialId: Number(r.material_id),
      cantidad: r.cantidad,
      tecnicoId: r.tecnico_id ? Number(r.tecnico_id) : null,
      nota: r.nota,
      fecha: r.fecha,
      idempotencyKey: r.idempotency_key,
      delta: r.delta
    })));
  } catch (e: any) {
    res.status(400).json({ message: String(e?.message ?? e) });
  }
});

export default router;
