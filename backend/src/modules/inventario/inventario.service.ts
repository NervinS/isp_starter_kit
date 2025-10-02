// src/modules/inventario/inventario.service.ts
import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { DataSource } from 'typeorm';
import { MovimientoDto, TipoMovimiento } from './dto/movimiento.dto';

type MovimientoInput = Omit<MovimientoDto, 'idempotencyKey' | 'tipo'> & {
  idempotencyKey?: string;
  tipo: TipoMovimiento;
  tecnicoId?: string | number;
};

function toText(v: unknown): string | undefined {
  if (v === null || v === undefined) return undefined;
  if (typeof v === 'number') return String(v);
  if (typeof v === 'string') return v.trim();
  return undefined;
}
function toIntId(v: unknown): number | undefined {
  if (typeof v === 'number' && Number.isInteger(v)) return v;
  const s = toText(v);
  if (!s) return undefined;
  const n = Number(s);
  if (!Number.isFinite(n) || !Number.isInteger(n)) return undefined;
  return n;
}

@Injectable()
export class InventarioService {
  constructor(private readonly ds: DataSource) {}

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  private async existsObject(name: string, kind: 'table' | 'view' | 'function') {
    if (kind === 'function') {
      const rows = await this.ds.query(
        `SELECT 1
           FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname='public' AND p.proname=$1
          LIMIT 1`,
        [name],
      );
      return !!rows?.length;
    }
    const rows = await this.ds.query(
      `SELECT 1
         FROM information_schema.${kind === 'table' ? 'tables' : 'views'}
        WHERE table_schema='public' AND table_name=$1
        LIMIT 1`,
      [name],
    );
    return !!rows?.length;
  }

  private async ensureMaterialExistsByIntId(materialIdInt: number) {
    const row = await this.ds.query(
      `SELECT id FROM materiales WHERE id = $1::int LIMIT 1`,
      [materialIdInt],
    );
    if (!row?.length) throw new NotFoundException('Material no existe');
  }

  private async getAlmacenIdDeTecnico(tecnicoId: number | string): Promise<string> {
    const rows = await this.ds.query(
      `SELECT id::text AS id
         FROM almacenes
        WHERE tipo='tecnico' AND tecnico_id=$1::int
        LIMIT 1`,
      [tecnicoId],
    );
    if (!rows?.length) throw new NotFoundException('Almacén de técnico no existe');
    return rows[0].id as string;
  }

  // ---------------------------------------------------------------------------
  // Lecturas
  // ---------------------------------------------------------------------------

  async getStockTecnico(tecnicoId: string) {
    const haveStockAlm = await this.existsObject('stock_almacen', 'table');
    if (haveStockAlm) {
      const almId = await this.getAlmacenIdDeTecnico(tecnicoId);
      return this.ds.query(
        `SELECT m.id::int AS "materialId",
                COALESCE(sa.cantidad,0)::int AS cantidad
           FROM materiales m
      LEFT JOIN stock_almacen sa
             ON sa.material_id = m.id AND sa.almacen_id = $1::uuid
       ORDER BY m.id`,
        [almId],
      );
    }

    // Fallback legacy
    return this.ds.query(
      `SELECT m.id::int AS "materialId",
              COALESCE(s.cantidad,0)::int AS cantidad
         FROM materiales m
    LEFT JOIN inventario_tecnico_stock s
           ON s.material_id = m.id AND s.tecnico_id = $1::int
     ORDER BY m.id`,
      [tecnicoId],
    );
  }

  async getStockGlobal() {
    const haveStockAlm = await this.existsObject('stock_almacen', 'table');
    if (haveStockAlm) {
      return this.ds.query(
        `SELECT m.id::int AS "materialId",
                COALESCE(SUM(sa.cantidad),0)::int AS cantidad
           FROM materiales m
      LEFT JOIN stock_almacen sa ON sa.material_id = m.id
       GROUP BY m.id
       ORDER BY m.id`,
      );
    }
    // Fallback legacy
    return this.ds.query(
      `SELECT m.id::int AS "materialId",
              COALESCE(SUM(s.cantidad),0)::int AS cantidad
         FROM materiales m
    LEFT JOIN inventario_tecnico_stock s ON s.material_id = m.id
     GROUP BY m.id
     ORDER BY m.id`,
    );
  }

  async getKardex() {
    // Preferida: vista v_kardex_det
    const haveKardexDet = await this.existsObject('v_kardex_det', 'view');
    if (haveKardexDet) {
      return this.ds.query(
        `SELECT id, fecha, tipo, material_id AS "materialId",
                material_codigo, material_nombre,
                almacen_id, almacen_codigo, almacen_nombre,
                from_almacen_id, from_almacen_codigo,
                to_almacen_id,   to_almacen_codigo,
                cantidad, delta, nota, tecnico_id
           FROM v_kardex_det
       ORDER BY fecha DESC, id DESC
          LIMIT 200`,
      );
    }
    // Fallback legacy
    const haveLegacy = await this.existsObject('inventario_movimientos', 'table');
    if (haveLegacy) {
      return this.ds.query(
        `SELECT id, fecha, tipo, referencia,
                material_id::int AS "materialId",
                cantidad::int    AS cantidad,
                tecnico_id, nota, user_id AS "userId",
                idem_key AS "idempotencyKey"
           FROM inventario_movimientos
       ORDER BY fecha DESC, id DESC
          LIMIT 200`,
      );
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // Escrituras
  // ---------------------------------------------------------------------------

  /**
   * Siempre usa wrappers estables en BD:
   *   - fn_mov_simple_std(tipo text, almacen_id uuid, material_id int, cantidad numeric, nota text)
   *   - fn_mov_traslado_std(from uuid, to uuid, material_id int, cantidad numeric, nota text)
   */
  private async movViaFunciones(
    tipo: 'ingreso' | 'egreso' | 'ajuste' | 'traslado',
    params: { almacenId?: string; fromId?: string; toId?: string; materialId: number; cantidad: number; nota?: string },
  ) {
    const haveSimpleStd = await this.existsObject('fn_mov_simple_std', 'function');
    const haveTrasStd   = await this.existsObject('fn_mov_traslado_std', 'function');

    if (tipo === 'traslado') {
      if (!haveTrasStd) return false;
      if (!params.fromId || !params.toId) throw new BadRequestException('from/to requeridos');

      await this.ds.transaction(async (manager) => {
        await manager.query(
          `SELECT public.fn_mov_traslado_std($1::uuid,$2::uuid,$3::int,$4::numeric,$5)`,
          [params.fromId, params.toId, params.materialId, params.cantidad, params.nota ?? null],
        );
      });
      return true;
    }

    if (!haveSimpleStd) return false;
    if (!params.almacenId) throw new BadRequestException('almacenId requerido');

    await this.ds.transaction(async (manager) => {
      await manager.query(
        `SELECT public.fn_mov_simple_std($1::text,$2::uuid,$3::int,$4::numeric,$5)`,
        [tipo, params.almacenId, params.materialId, params.cantidad, params.nota ?? null],
      );
    });
    return true;
  }

  private async legacyUpsertStockTecnico(
    tecnicoId: number,
    materialId: number,
    delta: number,
    setExact?: number,
  ) {
    await this.ds.query('BEGIN');
    try {
      const cur = await this.ds.query(
        `SELECT cantidad::int AS cantidad
           FROM inventario_tecnico_stock
          WHERE tecnico_id=$1::int AND material_id=$2::int
          FOR UPDATE`,
        [tecnicoId, materialId],
      );
      if (!cur.length) {
        const cantidad = setExact ?? Math.max(0, delta);
        await this.ds.query(
          `INSERT INTO inventario_tecnico_stock (tecnico_id, material_id, cantidad)
           VALUES ($1::int,$2::int,$3::int)`,
          [tecnicoId, materialId, cantidad],
        );
      } else {
        const actual = Number(cur[0].cantidad ?? 0);
        const nueva  = setExact !== undefined ? setExact : Math.max(0, actual + delta);
        if (nueva < 0) throw new ConflictException('saldo insuficiente');
        await this.ds.query(
          `UPDATE inventario_tecnico_stock
              SET cantidad=$3::int
            WHERE tecnico_id=$1::int AND material_id=$2::int`,
          [tecnicoId, materialId, nueva],
        );
      }
      await this.ds.query('COMMIT');
    } catch (e) {
      await this.ds.query('ROLLBACK');
      throw e;
    }
  }

  async crearMovimiento(input: MovimientoInput) {
    const tipo = input?.tipo;
    if (!tipo) throw new BadRequestException('tipo es requerido');

    let materialIdInt = toIntId(input.materialIdInt);
    if (materialIdInt === undefined) materialIdInt = toIntId(input.materialId);
    const cantidad = Number(input?.cantidad ?? 0);
    const tecnicoId = toIntId(input?.tecnicoId);

    if (!['ingreso', 'egreso', 'ajuste'].includes(tipo)) {
      throw new BadRequestException('tipo no soportado');
    }
    if (!tecnicoId) throw new BadRequestException('tecnicoId es requerido');
    if (materialIdInt === undefined) throw new BadRequestException('materialIdInt requerido');
    if (tipo !== 'ajuste' && (!Number.isFinite(cantidad) || cantidad <= 0)) {
      throw new BadRequestException('cantidad debe ser > 0');
    }

    await this.ensureMaterialExistsByIntId(materialIdInt);

    // Ruta preferida: funciones + stock_almacen
    const haveStockAlm = await this.existsObject('stock_almacen', 'table');
    if (haveStockAlm) {
      const almId = await this.getAlmacenIdDeTecnico(tecnicoId);
      if (tipo === 'ingreso') {
        await this.movViaFunciones('ingreso', {
          almacenId: almId, materialId: materialIdInt, cantidad, nota: input?.nota,
        });
      } else if (tipo === 'egreso') {
        // validación de saldo (sobre stock_almacen)
        const cur = await this.ds.query(
          `SELECT COALESCE(cantidad,0)::numeric AS cantidad
             FROM stock_almacen
            WHERE almacen_id=$1::uuid AND material_id=$2::int
            LIMIT 1`,
          [almId, materialIdInt],
        );
        const actual = Number(cur?.[0]?.cantidad ?? 0);
        if (actual < cantidad) throw new ConflictException('saldo insuficiente');
        await this.movViaFunciones('egreso', {
          almacenId: almId, materialId: materialIdInt, cantidad, nota: input?.nota,
        });
      } else {
        // ajuste "set": calculamos delta
        const cur = await this.ds.query(
          `SELECT COALESCE(cantidad,0)::numeric AS cantidad
             FROM stock_almacen
            WHERE almacen_id=$1::uuid AND material_id=$2::int
            LIMIT 1`,
          [almId, materialIdInt],
        );
        const actual = Number(cur?.[0]?.cantidad ?? 0);
        const delta  = cantidad - actual;
        if (delta === 0) return { ok: true, delta: 0 };
        if (delta > 0) {
          await this.movViaFunciones('ajuste', { almacenId: almId, materialId: materialIdInt, cantidad: delta, nota: input?.nota });
        } else {
          await this.movViaFunciones('egreso',  { almacenId: almId, materialId: materialIdInt, cantidad: -delta, nota: `[ajuste] ${input?.nota ?? ''}`.trim() });
        }
      }
      return { ok: true };
    }

    // Fallback legacy
    if (tipo === 'ingreso') {
      await this.legacyUpsertStockTecnico(tecnicoId, materialIdInt, cantidad);
    } else if (tipo === 'egreso') {
      const cur = await this.ds.query(
        `SELECT COALESCE(cantidad,0)::int AS cantidad
           FROM inventario_tecnico_stock
          WHERE tecnico_id=$1::int AND material_id=$2::int
          LIMIT 1`,
        [tecnicoId, materialIdInt],
      );
      const actual = Number(cur?.[0]?.cantidad ?? 0);
      if (actual < cantidad) throw new ConflictException('saldo insuficiente');
      await this.legacyUpsertStockTecnico(tecnicoId, materialIdInt, -cantidad);
    } else {
      await this.legacyUpsertStockTecnico(tecnicoId, materialIdInt, 0, cantidad);
    }

    // registra movimiento en tabla legacy si está
    if (await this.existsObject('inventario_movimientos', 'table')) {
      const idem = input.idempotencyKey ?? (globalThis as any)?.crypto?.randomUUID?.() ?? `idem-${Date.now()}`;
      await this.ds.query(
        `INSERT INTO inventario_movimientos
           (fecha, tipo, referencia, material_id, cantidad, tecnico_id, nota, user_id, idem_key)
         VALUES (NOW(), $1, $2, $3::int, $4::int, $5::int, $6, $7, $8)`,
        [
          tipo,
          `tecnico:${tecnicoId}`,
          materialIdInt,
          tipo === 'egreso' ? -cantidad : cantidad,
          tecnicoId,
          input?.nota ?? null,
          (input as any)?.userId ?? null,
          idem,
        ],
      );
    }

    return { ok: true };
  }

  // ---------------------------------------------------------------------------
  // Facades usadas por el controller actual
  // ---------------------------------------------------------------------------

  async agregar(tecnicoId: string, dto: Partial<MovimientoDto>) {
    return this.crearMovimiento({ ...dto, tipo: 'ingreso', tecnicoId });
  }
  async descontar(tecnicoId: string, dto: Partial<MovimientoDto>) {
    return this.crearMovimiento({ ...dto, tipo: 'egreso', tecnicoId });
  }
  async ajustar(tecnicoId: string, dto: Partial<MovimientoDto>) {
    return this.crearMovimiento({ ...dto, tipo: 'ajuste', tecnicoId, modoAjuste: 'set' });
  }
}
