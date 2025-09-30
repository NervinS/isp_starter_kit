// src/modules/inventario/inventario.service.ts
import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { DataSource } from 'typeorm';
import { MovimientoDto } from './dto/inventario.dto';

type TipoMovimiento = 'ingreso' | 'egreso' | 'transferencia' | 'ajuste';

/**
 * Convierte posibles entradas numéricas a texto “limpio”.
 */
function toText(v: unknown): string | undefined {
  if (v === null || v === undefined) return undefined;
  if (typeof v === 'number') return String(v);
  if (typeof v === 'string') return v.trim();
  return undefined;
}

/**
 * Convierte un id de material (int o string numérica) a int.
 */
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

  private async ensureMaterialExistsByIntId(materialIdInt: number) {
    const row = await this.ds.query(
      `
      SELECT m.id
      FROM materiales m
      WHERE m.id = $1::int
      LIMIT 1
      `,
      [materialIdInt],
    );
    if (!row?.length) {
      throw new NotFoundException('Material no existe');
    }
  }

  /**
   * Upsert del stock por técnico/material.
   * - tecnicoId se guarda como int en la tabla (castear si viene string).
   * - material_id es int (FK a materiales.id).
   */
  private async upsertStockTecnico(
    tecnicoId: string | number,
    materialIdInt: number,
    delta: number,
    setExacto?: number,
  ) {
    await this.ds.query('BEGIN');
    try {
      const cur = await this.ds.query(
        `
        SELECT cantidad
        FROM inventario_tecnico_stock
        WHERE tecnico_id = $1::int
          AND material_id = $2::int
        FOR UPDATE
        `,
        [tecnicoId, materialIdInt],
      );

      if (!cur.length) {
        const cantidad = setExacto ?? Math.max(0, delta);
        await this.ds.query(
          `
          INSERT INTO inventario_tecnico_stock (tecnico_id, material_id, cantidad)
          VALUES ($1::int, $2::int, $3::int)
          `,
          [tecnicoId, materialIdInt, cantidad],
        );
      } else {
        const actual = Number(cur[0].cantidad ?? 0);
        const nueva =
          setExacto !== undefined ? setExacto : Math.max(0, actual + delta);
        await this.ds.query(
          `
          UPDATE inventario_tecnico_stock
          SET cantidad = $3::int
          WHERE tecnico_id = $1::int
            AND material_id = $2::int
          `,
          [tecnicoId, materialIdInt, nueva],
        );
      }

      await this.ds.query('COMMIT');
    } catch (e) {
      await this.ds.query('ROLLBACK');
      throw e;
    }
  }

  // ---------------------------------------------------------------------------
  // Lecturas
  // ---------------------------------------------------------------------------

  async getStockTecnico(tecnicoId: string) {
    const rows = await this.ds.query(
      `
      SELECT m.id::int AS "materialId", s.cantidad::int AS cantidad
      FROM inventario_tecnico_stock s
      JOIN materiales m ON m.id = s.material_id
      WHERE s.tecnico_id = $1::int
      ORDER BY m.id
      `,
      [tecnicoId],
    );
    return rows;
  }

  async getStockGlobal() {
    return this.ds.query(
      `
      SELECT m.id::int AS "materialId", COALESCE(SUM(s.cantidad),0)::int AS cantidad
      FROM materiales m
      LEFT JOIN inventario_tecnico_stock s ON s.material_id = m.id
      GROUP BY m.id
      ORDER BY m.id
      `,
    );
  }

  async getKardex() {
    return this.ds.query(
      `
      SELECT
        id,
        fecha,
        tipo,
        referencia,
        material_id::int AS "materialId",
        cantidad::int AS cantidad,
        tecnico_id,
        nota,
        user_id AS "userId",
        idem_key AS "idempotencyKey"
      FROM inventario_movimientos
      ORDER BY fecha DESC, id DESC
      LIMIT 200
      `,
    );
  }

  // ---------------------------------------------------------------------------
  // Escrituras
  // ---------------------------------------------------------------------------

  /**
   * Crea un movimiento para el stock de técnico:
   * - ingreso: suma
   * - egreso: resta (sin permitir negativos)
   * - ajuste: fija cantidad exacta (modo "set")
   *
   * Acepta `materialIdInt` (preferido) o `materialId` si viene como string numérica.
   */
  async crearMovimiento(input: MovimientoDto & { tipo: TipoMovimiento; tecnicoId?: string }) {
    const tipo = input?.tipo;
    if (!tipo) throw new BadRequestException('tipo es requerido');

    // Resolver materialIdInt primero (preferido)
    let materialIdInt = toIntId(input.materialIdInt);
    if (materialIdInt === undefined) {
      // Intentar desde materialId (string numérica)
      materialIdInt = toIntId(input.materialId);
    }
    const cantidad = Number(input?.cantidad ?? 0);
    const tecnicoId = input?.tecnicoId;

    if (['ingreso', 'egreso', 'ajuste'].includes(tipo)) {
      if (!tecnicoId) throw new BadRequestException('tecnicoId es requerido');
      if (materialIdInt === undefined)
        throw new BadRequestException('materialIdInt requerido');

      if (tipo !== 'ajuste' && (!Number.isFinite(cantidad) || cantidad <= 0)) {
        throw new BadRequestException('cantidad debe ser > 0');
      }

      // Valida material (por id int)
      await this.ensureMaterialExistsByIntId(materialIdInt);

      // Aplica sobre stock de técnico
      if (tipo === 'ingreso') {
        await this.upsertStockTecnico(tecnicoId, materialIdInt, cantidad);
      } else if (tipo === 'egreso') {
        // Chequeo duro de saldo antes de descontar -> 409 si no alcanza
        const cur = await this.ds.query(
          `
          SELECT cantidad::int AS cantidad
          FROM inventario_tecnico_stock
          WHERE tecnico_id = $1::int AND material_id = $2::int
          LIMIT 1
          `,
          [tecnicoId, materialIdInt],
        );
        const actual = Number(cur?.[0]?.cantidad ?? 0);
        if (actual < cantidad) {
          throw new ConflictException('saldo insuficiente');
        }
        await this.upsertStockTecnico(tecnicoId, materialIdInt, -cantidad);
      } else {
        // ajuste (solo modo set por ahora)
        const modo = input.modoAjuste ?? 'set';
        if (modo !== 'set') {
          throw new BadRequestException('modoAjuste inválido');
        }
        await this.upsertStockTecnico(tecnicoId, materialIdInt, 0, cantidad);
      }

      // Registra en kardex/movimientos
      const mov = await this.ds.query(
        `
        INSERT INTO inventario_movimientos
          (fecha, tipo, referencia, material_id, cantidad, tecnico_id, nota, user_id, idem_key)
        VALUES (NOW(), $1, $2, $3::int, $4::int, $5::int, $6, $7, $8)
        RETURNING id
        `,
        [
          tipo,
          `tecnico:${tecnicoId}`,
          materialIdInt,
          tipo === 'egreso' ? -cantidad : cantidad,
          tecnicoId,
          input?.nota ?? null,
          input?.userId ?? null,
          input?.idempotencyKey ?? null,
        ],
      );

      return { id: mov[0]?.id };
    }

    throw new BadRequestException('tipo no soportado');
  }

  // ---------------------------------------------------------------------------
  // Facades azucarados para el controller (si los usas)
  // ---------------------------------------------------------------------------

  async agregar(tecnicoId: string, dto: MovimientoDto) {
    return this.crearMovimiento({ ...dto, tipo: 'ingreso', tecnicoId });
  }

  async descontar(tecnicoId: string, dto: MovimientoDto) {
    return this.crearMovimiento({ ...dto, tipo: 'egreso', tecnicoId });
  }

  async ajustar(tecnicoId: string, dto: MovimientoDto) {
    return this.crearMovimiento({ ...dto, tipo: 'ajuste', tecnicoId });
  }
}
