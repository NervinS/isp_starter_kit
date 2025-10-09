import { Router, Request, Response } from "express";
import { Pool } from "pg";

const router = Router();
const pool = new Pool({
  connectionString: process.env.DATABASE_URL, // o tus vars separadas
});

type Movimiento = {
  id: string;
  tipo: "ingreso" | "egreso" | "ajuste" | "transferencia" | "traslado";
  material_id: number;
  cantidad: string; // numeric viene como string
  tecnico_id: number | null;
  nota: string | null;
  idempotency_key: string | null;
  delta: string;
};

function mapOut(row: any) {
  return {
    ok: true,
    id: String(row.id),
    tipo: row.tipo,
    materialId: Number(row.material_id),
    cantidad: row.cantidad,
    tecnicoId: row.tecnico_id ? Number(row.tecnico_id) : null,
    nota: row.nota ?? null,
    _idempotent: !!row._idempotent,
  };
}

/**
 * Inserta un movimiento idempotente:
 * - Primer intento: INSERT -> 201, _idempotent=false
 * - Reintento (misma Idempotency-Key): SELECT existente -> 200, _idempotent=true
 */
async function insertMovimientoIdempotente(params: {
  idemp: string | null;
  tipo: Movimiento["tipo"];
  materialId: number;
  cantidad: number;
  tecnicoId?: number | null;
  nota?: string | null;
}): Promise<{ row: Movimiento & { _idempotent: boolean }; http: 200 | 201 }> {
  const client = await pool.connect();
  try {
    const { idemp, tipo, materialId, cantidad, tecnicoId, nota } = params;

    const sql = `
      WITH ins AS (
        INSERT INTO public.movimientos (tipo, cantidad, material_id, tecnico_id, nota, idempotency_key)
        VALUES ($1::movimiento_tipo, $2, $3, $4, $5, $6)
        ON CONFLICT (idempotency_key) DO NOTHING
        RETURNING *
      )
      SELECT *, FALSE AS _idempotent FROM ins
      UNION ALL
      SELECT m.*, TRUE AS _idempotent
      FROM public.movimientos m
      WHERE m.idempotency_key = $6
      LIMIT 1;
    `;

    const values = [
      tipo,
      cantidad,
      materialId,
      tecnicoId ?? null,
      nota ?? null,
      idemp,
    ];

    const { rows } = await client.query(sql, values);
    if (!rows[0]) {
      throw new Error("No se pudo recuperar el movimiento (idempotencia).");
    }
    const row = rows[0] as Movimiento & { _idempotent: boolean };
    const http = row._idempotent ? 200 : 201;
    return { row, http };
  } finally {
    client.release();
  }
}

// --- Rutas ---------------------------------------------------------------

/**
 * Semántica de dominio (común en estos kits):
 *   - agregar   => traslado desde almacén central hacia técnico (no cambia total del sistema)
 *   - descontar => traslado desde técnico hacia almacén central
 * Si tu dominio prefiere 'ingreso/egreso', cambia 'tipo' aquí y listo (trigger de delta ya lo respeta).
 */

router.post("/v1/inventario/tecnicos/:tecnicoId/agregar", async (req: Request, res: Response) => {
  try {
    const tecnicoId = Number(req.params.tecnicoId);
    const { materialId, cantidad, nota } = req.body ?? {};
    if (!Number.isFinite(tecnicoId) || !Number.isFinite(materialId) || !Number.isFinite(cantidad)) {
      return res.status(400).json({ message: "Parámetros inválidos" });
    }
    const idemp = (req.get("Idempotency-Key") ?? null);

    const { row, http } = await insertMovimientoIdempotente({
      idemp,
      tipo: "traslado",          // ver nota arriba
      materialId: Number(materialId),
      cantidad: Number(cantidad),
      tecnicoId,
      nota: nota ?? "agregar (traslado central→técnico)",
    });

    return res.status(http).json(mapOut(row));
  } catch (err: any) {
    return res.status(400).json({ message: String(err?.message ?? err) });
  }
});

router.post("/v1/inventario/tecnicos/:tecnicoId/descontar", async (req: Request, res: Response) => {
  try {
    const tecnicoId = Number(req.params.tecnicoId);
    const { materialId, cantidad, nota } = req.body ?? {};
    if (!Number.isFinite(tecnicoId) || !Number.isFinite(materialId) || !Number.isFinite(cantidad)) {
      return res.status(400).json({ message: "Parámetros inválidos" });
    }
    const idemp = (req.get("Idempotency-Key") ?? null);

    const { row, http } = await insertMovimientoIdempotente({
      idemp,
      tipo: "traslado",          // traslado técnico→central (la capa de dominio resuelve sentido)
      materialId: Number(materialId),
      cantidad: Number(cantidad),
      tecnicoId,
      nota: nota ?? "descontar (traslado técnico→central)",
    });

    return res.status(http).json(mapOut(row));
  } catch (err: any) {
    return res.status(400).json({ message: String(err?.message ?? err) });
  }
});

export default router;
