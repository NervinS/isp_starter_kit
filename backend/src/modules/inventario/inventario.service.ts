// src/modules/inventario/inventario.service.ts
import { Injectable, ConflictException } from '@nestjs/common';
import { DataSource, QueryRunner } from 'typeorm';

export type MovimientoInput = {
  // Acepta ambos en la entrada; internamente se normaliza a 'traslado'
  tipo: 'ingreso' | 'egreso' | 'ajuste' | 'traslado' | 'transferencia';
  materialId: number | string;
  cantidad: number | string;
  fromAlmacenId?: string | null;
  toAlmacenId?: string | null;
  tecnicoId?: number | string | null;
  nota?: string | null;
};

type MovimientoRow = {
  id: string;
  tipo: string;
  material_id: number;
  cantidad: number;
  almacen_origen_id: string | null;
  almacen_destino_id: string | null;
  tecnico_id: number | null;
  nota: string | null;
};

@Injectable()
export class InventarioService {
  constructor(private readonly dataSource: DataSource) {}

  // ----------------- Helpers -----------------
  private async getAlmacenIdByCodigo(codigo: string): Promise<string | null> {
    const rows = (await this.dataSource.query(
      `SELECT id FROM public.almacenes WHERE codigo = $1 LIMIT 1`,
      [codigo],
    )) as any[];
    return rows?.[0]?.id ?? null;
  }

  /** Resuelve el almacén "principal" sin depender del nombre exacto. */
  private async getMainWarehouseId(): Promise<string> {
    const envCode = (process.env.MAIN_WAREHOUSE_CODE || '').trim().toUpperCase();
    if (envCode) {
      const viaEnv = await this.getAlmacenIdByCodigo(envCode);
      if (viaEnv) return viaEnv;
    }
    const central = await this.getAlmacenIdByCodigo('CENTRAL');
    if (central) return central;
    const principal = await this.getAlmacenIdByCodigo('PRINCIPAL');
    if (principal) return principal;

    throw new Error(
      'No se encontró almacén principal (revisa MAIN_WAREHOUSE_CODE o crea CENTRAL/PRINCIPAL)',
    );
  }

  private toNum(n: unknown): number | null {
    const x = Number(n);
    return Number.isFinite(x) ? x : null;
  }

  // ----------------- Stock (consultas) -----------------

  /**
   * Overload para aceptar:
   *  - (codigo: string, materialId?: number)
   *  - ({ almacenCodigo, materialId })
   */
  async getStockPorAlmacenCodigo(
    codigoOrObj: string | { almacenCodigo: string; materialId?: number },
    materialIdMaybe?: number,
  ) {
    const codigo = typeof codigoOrObj === 'string' ? codigoOrObj : codigoOrObj.almacenCodigo;

    const materialId =
      typeof codigoOrObj === 'string' ? materialIdMaybe : codigoOrObj.materialId;

    const params: any[] = [codigo];
    let whereMaterial = '';
    if (typeof materialId === 'number' && !Number.isNaN(materialId)) {
      whereMaterial = 'AND sa.material_id = $2';
      params.push(materialId);
    }

    const sql = `
      SELECT
        a.id              AS almacen_id,
        a.codigo          AS almacen_codigo,
        a.nombre          AS almacen_nombre,
        sa.material_id    AS material_id,
        m.codigo          AS material_codigo,
        m.nombre          AS material_nombre,
        sa.cantidad       AS cantidad
      FROM public.almacenes a
      JOIN public.stock_almacen sa ON sa.almacen_id = a.id
      JOIN public.materiales m     ON m.id = sa.material_id
      WHERE a.codigo = $1
      ${whereMaterial}
      ORDER BY m.id;
    `;
    return this.dataSource.query(sql, params);
  }

  /**
   * Overload para aceptar:
   *  - (materialId?: number)
   *  - ({ materialId?: number })
   */
  async getStockGlobal(material?: number | { materialId?: number }) {
    const materialId = typeof material === 'number' ? material : material?.materialId;

    const params: any[] = [];
    let whereMaterial = '';
    if (typeof materialId === 'number' && !Number.isNaN(materialId)) {
      whereMaterial = 'WHERE sa.material_id = $1';
      params.push(materialId);
    }

    const sql = `
      SELECT
        a.id           AS almacen_id,
        a.codigo       AS almacen_codigo,
        a.nombre       AS almacen_nombre,
        sa.material_id AS material_id,
        m.codigo       AS material_codigo,
        m.nombre       AS material_nombre,
        sa.cantidad    AS cantidad
      FROM public.stock_almacen sa
      JOIN public.almacenes a ON a.id = sa.almacen_id
      JOIN public.materiales m ON m.id = sa.material_id
      ${whereMaterial}
      ORDER BY a.codigo, m.id;
    `;
    return this.dataSource.query(sql, params);
  }

  /**
   * Stock del técnico: se basa en almacén con código TEC-{tecnicoId}
   */
  async getStockTecnico(tecnicoId: number | string) {
    const tId = this.toNum(tecnicoId);
    if (!tId) throw new Error('tecnicoId inválido');
    const codigoTec = `TEC-${tId}`;
    return this.getStockPorAlmacenCodigo(codigoTec);
  }

  // ----------------- Kardex -----------------

  async getKardex(limit = 50) {
    const lim = Number.isFinite(limit) && limit > 0 ? Math.min(limit, 500) : 50;

    const sql = `
      SELECT
        m.created_at                                  AS fecha,
        m.tipo                                        AS tipo,
        m.material_id                                 AS "materialId",
        mat.codigo                                    AS material_codigo,
        mat.nombre                                    AS material_nombre,
        COALESCE(m.almacen_destino_id, m.almacen_origen_id) AS almacen_id,
        COALESCE(ad.codigo, ao.codigo)                AS almacen_codigo,
        COALESCE(ad.nombre, ao.nombre)                AS almacen_nombre,
        m.almacen_origen_id                           AS from_almacen_id,
        ao.codigo                                     AS from_almacen_codigo,
        m.almacen_destino_id                          AS to_almacen_id,
        ad.codigo                                     AS to_almacen_codigo,
        m.cantidad                                    AS cantidad,
        CASE
          WHEN m.tipo = 'ingreso' THEN m.cantidad
          WHEN m.tipo = 'egreso'  THEN -m.cantidad
          ELSE 0
        END                                           AS delta,
        m.nota                                        AS nota,
        m.tecnico_id                                  AS tecnico_id
      FROM public.movimientos m
      JOIN public.materiales mat ON mat.id = m.material_id
      LEFT JOIN public.almacenes ao ON ao.id = m.almacen_origen_id
      LEFT JOIN public.almacenes ad ON ad.id = m.almacen_destino_id
      ORDER BY m.created_at DESC
      LIMIT $1;
    `;
    return this.dataSource.query(sql, [lim]);
  }

  // ----------------- SQL para mutaciones de stock -----------------

  private readonly SQL_STOCK_SELECT_FOR_UPDATE = `
    SELECT cantidad
    FROM public.stock_almacen
    WHERE almacen_id = $1 AND material_id = $2
    FOR UPDATE
  `;

  private readonly SQL_STOCK_UPSERT_ADD = `
    INSERT INTO public.stock_almacen(almacen_id, material_id, cantidad)
    VALUES ($1, $2, $3)
    ON CONFLICT (almacen_id, material_id)
    DO UPDATE SET cantidad = public.stock_almacen.cantidad + EXCLUDED.cantidad
    RETURNING cantidad
  `;

  private readonly SQL_STOCK_UPDATE_SUB_GUARDED = `
    UPDATE public.stock_almacen
    SET cantidad = cantidad - $3
    WHERE almacen_id = $1
      AND material_id = $2
      AND cantidad >= $3
    RETURNING cantidad
  `;

  // ----------------- Idempotencia: helpers -----------------

  private async insertMovimientoIdemFirst(
    qr: QueryRunner,
    draft: Omit<MovimientoRow, 'id'>,
    idempotencyKey?: string,
  ): Promise<{ row: MovimientoRow | null; idempotentHit: MovimientoRow | null }> {
    if (!idempotencyKey) {
      // Sin idem-key: no insertamos todavía; devolvemos nulo
      return { row: null, idempotentHit: null };
    }

    const inserted = (await qr.query(
      `
      INSERT INTO public.movimientos
        (tipo, material_id, cantidad, almacen_origen_id, almacen_destino_id, tecnico_id, nota, fecha, created_at, idempotency_key)
      VALUES
        ($1,   $2,          $3,       $4,                $5,                 $6,         $7,   NOW(), NOW(),     $8)
      ON CONFLICT (idempotency_key) DO NOTHING
      RETURNING id, tipo, material_id, cantidad, almacen_origen_id, almacen_destino_id, tecnico_id, nota
      `,
      [
        draft.tipo,
        draft.material_id,
        draft.cantidad,
        draft.almacen_origen_id,
        draft.almacen_destino_id,
        draft.tecnico_id,
        draft.nota,
        idempotencyKey,
      ],
    )) as any[];

    if (inserted && inserted[0]) {
      return { row: inserted[0] as MovimientoRow, idempotentHit: null };
    }

    const hit = (await qr.query(
      `
      SELECT id, tipo, material_id, cantidad, almacen_origen_id, almacen_destino_id, tecnico_id, nota
      FROM public.movimientos
      WHERE idempotency_key = $1
      LIMIT 1
      `,
      [idempotencyKey],
    )) as any[];

    return { row: null, idempotentHit: (hit?.[0] as MovimientoRow) ?? null };
  }

  private async insertMovimientoFinally(qr: QueryRunner, row: Omit<MovimientoRow, 'id'>) {
    const inserted = (await qr.query(
      `
      INSERT INTO public.movimientos
        (tipo, material_id, cantidad, almacen_origen_id, almacen_destino_id, tecnico_id, nota, fecha, created_at)
      VALUES
        ($1,   $2,          $3,       $4,                $5,                 $6,         $7,   NOW(), NOW())
      RETURNING id, tipo, material_id, cantidad, almacen_origen_id, almacen_destino_id, tecnico_id, nota
      `,
      [
        row.tipo,
        row.material_id,
        row.cantidad,
        row.almacen_origen_id,
        row.almacen_destino_id,
        row.tecnico_id,
        row.nota,
      ],
    )) as any[];
    return inserted[0] as MovimientoRow;
  }

  private mapOut(row: MovimientoRow, idempotent: boolean) {
    return {
      ok: true,
      id: row.id,
      tipo: row.tipo,
      materialId: row.material_id,
      cantidad: row.cantidad,
      fromAlmacenId: row.almacen_origen_id,
      toAlmacenId: row.almacen_destino_id,
      tecnicoId: row.tecnico_id,
      nota: row.nota,
      _idempotent: idempotent,
    };
  }

  // ----------------- Primitivas de stock -----------------

  private async ensureStockRow(qr: QueryRunner, almacenId: string, matId: number) {
    await qr.query(
      `
      INSERT INTO public.stock_almacen(almacen_id, material_id, cantidad)
      VALUES ($1, $2, 0)
      ON CONFLICT (almacen_id, material_id) DO NOTHING
      `,
      [almacenId, matId],
    );
  }

  private async getCantidad(qr: QueryRunner, almacenId: string, matId: number): Promise<number> {
    const r = (await qr.query(
      `SELECT cantidad FROM public.stock_almacen WHERE almacen_id = $1 AND material_id = $2`,
      [almacenId, matId],
    )) as any[];
    return Number(r?.[0]?.cantidad ?? 0);
  }

  private async addStock(qr: QueryRunner, almacenId: string, matId: number, qty: number) {
    await qr.query(this.SQL_STOCK_UPSERT_ADD, [almacenId, matId, qty]);
  }

  private async subStock(qr: QueryRunner, almacenId: string, matId: number, qty: number) {
    await this.ensureStockRow(qr, almacenId, matId);

    // Pre-check explícito de saldo (determinista)
    const actualAntes = await this.getCantidad(qr, almacenId, matId);
    if (qty > actualAntes) {
      throw new ConflictException(
        `Saldo insuficiente en almacén ${almacenId} para material ${matId}, requerido ${qty}, actual ${actualAntes}`,
      );
    }

    // Guard adicional por concurrencia
    const res = (await qr.query(this.SQL_STOCK_UPDATE_SUB_GUARDED, [
      almacenId,
      matId,
      qty,
    ])) as any[];
    if (!res?.[0]) {
      const actual = await this.getCantidad(qr, almacenId, matId);
      throw new ConflictException(
        `Saldo insuficiente en almacén ${almacenId} para material ${matId}, requerido ${qty}, actual ${actual}`,
      );
    }
  }

  // ----------------- Movimientos genéricos (transaccional + idempotente) -----------------

  /**
   * Aplica un movimiento con soporte de idempotencia (si se pasa Idempotency-Key).
   * - ingreso: +stock en toAlmacenId, 1 fila 'ingreso'
   * - egreso:  -stock en fromAlmacenId, 1 fila 'egreso'
   * - ajuste:  si trae toAlmacenId => suma; si trae fromAlmacenId => resta
   * - traslado/transferencia: resta origen, suma destino, 1 fila 'traslado'
   */
  async crearMovimiento(input: MovimientoInput, idempotencyKey?: string) {
    const materialId = this.toNum(input.materialId);
    const cantidad = this.toNum(input.cantidad);
    const tecnicoId =
      input.tecnicoId === undefined || input.tecnicoId === null
        ? null
        : this.toNum(input.tecnicoId);

    if (!materialId || materialId <= 0) throw new Error('materialId inválido');
    if (!cantidad || cantidad <= 0) throw new Error('cantidad inválida');

    const fromId = input.fromAlmacenId ?? null;
    const toId = input.toAlmacenId ?? null;
    const nota = input.nota ?? null;

    // Normaliza: 'transferencia' (entrada) -> 'traslado' (DB)
    const tipoIn = input.tipo === 'transferencia' ? 'traslado' : input.tipo;

    const qr = this.dataSource.createQueryRunner();
    await qr.connect();
    await qr.startTransaction();

    const draft: Omit<MovimientoRow, 'id'> = {
      tipo: tipoIn,
      material_id: materialId,
      cantidad,
      almacen_origen_id: fromId,
      almacen_destino_id: toId,
      tecnico_id: tecnicoId ?? null,
      nota,
    };

    try {
      // 1) Insert previo si hay Idempotency-Key (reserva dentro de la tx)
      let insertedRow: MovimientoRow | null = null;
      if (idempotencyKey) {
        const { row, idempotentHit } = await this.insertMovimientoIdemFirst(
          qr,
          draft,
          idempotencyKey,
        );
        if (idempotentHit) {
          // Ya existía => NO tocamos stock
          await qr.rollbackTransaction();
          await qr.release();
          return this.mapOut(idempotentHit, true);
        }
        insertedRow = row; // si vino, usaremos este ID al final
      }

      // 2) Aplica el efecto de stock según tipo
      if (tipoIn === 'traslado') {
        if (!fromId || !toId) {
          throw new Error('traslado requiere fromAlmacenId y toAlmacenId');
        }
        await this.subStock(qr, fromId, materialId, cantidad);
        await this.addStock(qr, toId, materialId, cantidad);
      } else if (tipoIn === 'ingreso') {
        if (!toId) throw new Error('ingreso requiere toAlmacenId');
        await this.addStock(qr, toId, materialId, cantidad);
      } else if (tipoIn === 'egreso') {
        if (!fromId) throw new Error('egreso requiere fromAlmacenId');
        await this.subStock(qr, fromId, materialId, cantidad);
      } else if (tipoIn === 'ajuste') {
        if (toId && !fromId) {
          await this.addStock(qr, toId, materialId, cantidad);
        } else if (fromId && !toId) {
          await this.subStock(qr, fromId, materialId, cantidad);
        } else {
          throw new Error(
            'ajuste requiere **solo** toAlmacenId (sumar) o **solo** fromAlmacenId (restar)',
          );
        }
      } else {
        throw new Error(`tipo de movimiento no soportado: ${input.tipo}`);
      }

      // 3) Registrar movimiento si no se insertó arriba
      let finalRow: MovimientoRow;
      if (insertedRow) {
        finalRow = insertedRow;
      } else {
        finalRow = await this.insertMovimientoFinally(qr, draft);
      }

      await qr.commitTransaction();
      return this.mapOut(finalRow, false);
    } catch (err: any) {
      await qr.rollbackTransaction();
      if (err instanceof ConflictException) {
        throw err;
      }
      const msg = err?.message || 'Error al aplicar movimiento';
      throw new Error(msg);
    } finally {
      await qr.release();
    }
  }

  // ----------------- Acciones específicas de técnico -----------------

  /** MAIN -> TEC-{tecnicoId} */
  async agregarATecnico(
    params: {
      tecnicoId: number | string;
      materialId: number | string;
      cantidad: number | string;
      nota?: string | null;
    },
    idempotencyKey?: string,
  ) {
    const tId = this.toNum(params.tecnicoId);
    const materialId = this.toNum(params.materialId);
    const cantidad = this.toNum(params.cantidad);
    if (!tId) throw new Error('tecnicoId inválido');
    if (!materialId) throw new Error('materialId inválido');
    if (!cantidad || cantidad <= 0) throw new Error('cantidad inválida');

    const mainId = await this.getMainWarehouseId();
    const tecId = await this.getAlmacenIdByCodigo(`TEC-${tId}`);
    if (!mainId) throw new Error('Almacén principal no existe');
    if (!tecId) throw new Error(`Almacén TEC-${tId} no existe`);

    return this.crearMovimiento(
      {
        tipo: 'traslado', // normaliza
        materialId,
        cantidad,
        fromAlmacenId: mainId,
        toAlmacenId: tecId,
        tecnicoId: tId,
        nota: params.nota ?? null,
      },
      idempotencyKey,
    );
  }

  /** TEC-{tecnicoId} -> MAIN */
  async descontarATecnico(
    params: {
      tecnicoId: number | string;
      materialId: number | string;
      cantidad: number | string;
      nota?: string | null;
    },
    idempotencyKey?: string,
  ) {
    const tId = this.toNum(params.tecnicoId);
    const materialId = this.toNum(params.materialId);
    const cantidad = this.toNum(params.cantidad);
    if (!tId) throw new Error('tecnicoId inválido');
    if (!materialId) throw new Error('materialId inválido');
    if (!cantidad || cantidad <= 0) throw new Error('cantidad inválida');

    const mainId = await this.getMainWarehouseId();
    const tecId = await this.getAlmacenIdByCodigo(`TEC-${tId}`);
    if (!mainId) throw new Error('Almacén principal no existe');
    if (!tecId) throw new Error(`Almacén TEC-${tId} no existe`);

    return this.crearMovimiento(
      {
        tipo: 'traslado', // normaliza
        materialId,
        cantidad,
        fromAlmacenId: tecId,
        toAlmacenId: mainId,
        tecnicoId: tId,
        nota: params.nota ?? null,
      },
      idempotencyKey,
    );
  }

  /** Ajuste sobre TEC-{tecnicoId}: signo 'mas' suma, 'menos' resta */
  async ajustarTecnico(
    params: {
      tecnicoId: number | string;
      materialId: number | string;
      cantidad: number | string; // valor absoluto del ajuste
      signo: 'mas' | 'menos'; // para saber si suma o resta
      nota?: string | null;
    },
    idempotencyKey?: string,
  ) {
    const tId = this.toNum(params.tecnicoId);
    const materialId = this.toNum(params.materialId);
    const cantidadBase = this.toNum(params.cantidad);
    if (!tId) throw new Error('tecnicoId inválido');
    if (!materialId) throw new Error('materialId inválido');
    if (!cantidadBase || cantidadBase <= 0) throw new Error('cantidad inválida');

    const tecId = await this.getAlmacenIdByCodigo(`TEC-${tId}`);
    if (!tecId) throw new Error(`Almacén TEC-${tId} no existe`);

    if (params.signo === 'menos') {
      return this.crearMovimiento(
        {
          tipo: 'ajuste',
          materialId,
          cantidad: cantidadBase,
          fromAlmacenId: tecId,
          toAlmacenId: null,
          tecnicoId: tId,
          nota: params.nota ?? 'ajuste técnico (-)',
        },
        idempotencyKey,
      );
    }

    // 'mas'
    return this.crearMovimiento(
      {
        tipo: 'ajuste',
        materialId,
        cantidad: cantidadBase,
        fromAlmacenId: null,
        toAlmacenId: tecId,
        tecnicoId: tId,
        nota: params.nota ?? 'ajuste técnico (+)',
      },
      idempotencyKey,
    );
  }
}
