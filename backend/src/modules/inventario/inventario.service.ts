// src/modules/inventario/inventario.service.ts
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { DataSource } from 'typeorm';

type TipoMovimiento = 'ingreso' | 'egreso' | 'transferencia' | 'ajuste';

interface CrearMovimientoDto {
  idempotencyKey?: string;
  tipo: TipoMovimiento;
  almacenOrigenId?: string;
  almacenDestinoId?: string;
  materialIdInt?: number;
  materialId?: string | number;
  cantidad?: number | string;
  cantidadSigned?: number | string;
  motivo?: string | null;
  refExterna?: string | null;
  evidenciaKey?: string | null;
}

interface AjusteDto {
  materialIdInt?: number;
  materialId?: string | number;
  cantidadSigned: number | string;
  motivo?: string | null;
  refExterna?: string | null;
  evidenciaKey?: string | null;
}

interface SimpleOpDto {
  materialIdInt?: number;
  materialId?: string | number;
  cantidad: number | string;
  motivo?: string | null;
  refExterna?: string | null;
  evidenciaKey?: string | null;
}

@Injectable()
export class InventarioService {
  constructor(private readonly dataSource: DataSource) {}

  // ================== QUERIES PÚBLICAS ==================

  async listarStockDeTecnico(tecnicoId: string) {
    const rows = await this.dataSource.query(
      `
      SELECT material_id AS "materialId", cantidad
      FROM inv_tecnico
      WHERE tecnico_id = $1
      ORDER BY material_id ASC
    `,
      [tecnicoId],
    );
    return rows.map((r: any) => ({
      materialId: Number(r.materialId),
      cantidad: Number(r.cantidad ?? 0),
    }));
  }

  // -------- descontarStock (overloads compatibles) --------
  async descontarStock(
    tecnicoId: string,
    dto: SimpleOpDto,
    userId?: string,
  ): Promise<{ id: string }>;
  async descontarStock(
    tecnicoId: string,
    materialIdInt: number | string,
    cantidad: number | string,
    userId?: string,
  ): Promise<{ id: string }>;
  async descontarStock(
    tecnicoId: string,
    p2: any,
    p3?: any,
    p4?: any,
  ): Promise<{ id: string }> {
    const almacenTec = await this.getAlmacenDeTecnico(tecnicoId);
    if (!almacenTec) throw new NotFoundException('Almacén de técnico no existe');

    let dto: SimpleOpDto;
    let userId: string | undefined;
    if (typeof p2 === 'number' || typeof p2 === 'string') {
      dto = { materialIdInt: Number(p2), cantidad: Number(p3) };
      userId = p4;
    } else {
      dto = p2 as SimpleOpDto;
      userId = p3;
    }

    const materialId =
      dto.materialIdInt ??
      (dto.materialId !== undefined ? Number(dto.materialId) : NaN);
    const cantidad = Number(dto.cantidad);
    if (!Number.isInteger(materialId) || materialId <= 0)
      throw new BadRequestException('materialId inválido');
    if (!Number.isFinite(cantidad) || cantidad <= 0)
      throw new BadRequestException('cantidad > 0 requerida');

    return this.crearMovimiento(
      {
        idempotencyKey: dto.refExterna,
        tipo: 'egreso',
        almacenOrigenId: almacenTec,
        materialIdInt: materialId,
        cantidad,
        motivo: dto.motivo ?? null,
        refExterna: dto.refExterna ?? null,
        evidenciaKey: dto.evidenciaKey ?? null,
      },
      userId,
    );
  }

  // -------- agregarStock (overloads compatibles) --------
  async agregarStock(
    tecnicoId: string,
    dto: SimpleOpDto,
    userId?: string,
  ): Promise<{ id: string }>;
  async agregarStock(
    tecnicoId: string,
    materialIdInt: number | string,
    cantidad: number | string,
    userId?: string,
  ): Promise<{ id: string }>;
  async agregarStock(
    tecnicoId: string,
    p2: any,
    p3?: any,
    p4?: any,
  ): Promise<{ id: string }> {
    const almacenTec = await this.getAlmacenDeTecnico(tecnicoId);
    if (!almacenTec) throw new NotFoundException('Almacén de técnico no existe');

    let dto: SimpleOpDto;
    let userId: string | undefined;
    if (typeof p2 === 'number' || typeof p2 === 'string') {
      dto = { materialIdInt: Number(p2), cantidad: Number(p3) };
      userId = p4;
    } else {
      dto = p2 as SimpleOpDto;
      userId = p3;
    }

    const materialId =
      dto.materialIdInt ??
      (dto.materialId !== undefined ? Number(dto.materialId) : NaN);
    const cantidad = Number(dto.cantidad);
    if (!Number.isInteger(materialId) || materialId <= 0)
      throw new BadRequestException('materialId inválido');
    if (!Number.isFinite(cantidad) || cantidad <= 0)
      throw new BadRequestException('cantidad > 0 requerida');

    return this.crearMovimiento(
      {
        idempotencyKey: dto.refExterna,
        tipo: 'ingreso',
        almacenDestinoId: almacenTec,
        materialIdInt: materialId,
        cantidad,
        motivo: dto.motivo ?? null,
        refExterna: dto.refExterna ?? null,
        evidenciaKey: dto.evidenciaKey ?? null,
      },
      userId,
    );
  }

  // -------- ajustarStock (overloads compatibles) --------
  async ajustarStock(
    tecnicoId: string,
    dto: AjusteDto,
    userId?: string,
  ): Promise<{ id: string }>;
  async ajustarStock(
    tecnicoId: string,
    materialIdInt: number | string,
    cantidadSigned: number | string,
    userId?: string,
  ): Promise<{ id: string }>;
  async ajustarStock(
    tecnicoId: string,
    p2: any,
    p3?: any,
    p4?: any,
  ): Promise<{ id: string }> {
    const almacenTec = await this.getAlmacenDeTecnico(tecnicoId);
    if (!almacenTec) throw new NotFoundException('Almacén de técnico no existe');

    let dto: AjusteDto;
    let userId: string | undefined;
    if (typeof p2 === 'number' || typeof p2 === 'string') {
      dto = { materialIdInt: Number(p2), cantidadSigned: Number(p3) };
      userId = p4;
    } else {
      dto = p2 as AjusteDto;
      userId = p3;
    }

    const materialId =
      dto.materialIdInt ??
      (dto.materialId !== undefined ? Number(dto.materialId) : NaN);
    const cantidadSigned = Number(dto.cantidadSigned);
    if (!Number.isInteger(materialId) || materialId <= 0)
      throw new BadRequestException('materialId inválido');
    if (!Number.isFinite(cantidadSigned))
      throw new BadRequestException('cantidadSigned requerida');

    return this.crearMovimiento(
      {
        idempotencyKey: dto.refExterna,
        tipo: 'ajuste',
        almacenDestinoId: almacenTec,
        materialIdInt: materialId,
        cantidadSigned,
        motivo: dto.motivo ?? null,
        refExterna: dto.refExterna ?? null,
        evidenciaKey: dto.evidenciaKey ?? null,
      },
      userId,
    );
  }

  // -------- getStockCorporativo (compat múltiples args) --------
  async getStockCorporativo(scope?: string): Promise<any[]>;
  async getStockCorporativo(scope?: string, _unused?: any): Promise<any[]>;
  async getStockCorporativo(scope?: string): Promise<any[]> {
    if (scope === 'principal') {
      return this.dataSource.query(
        `
        SELECT a.id AS "almacenId", a.tipo, s.material_id AS "materialId", COALESCE(s.cantidad,0) AS cantidad
        FROM almacenes a
        LEFT JOIN stock_almacen s ON s.almacen_id = a.id
        WHERE a.tipo = 'principal'
        ORDER BY a.id, s.material_id
      `,
      );
    }
    return this.dataSource.query(
      `
      SELECT a.id AS "almacenId", a.tipo, s.material_id AS "materialId", COALESCE(s.cantidad,0) AS cantidad
      FROM almacenes a
      LEFT JOIN stock_almacen s ON s.almacen_id = a.id
      ORDER BY a.tipo, a.id, s.material_id
    `,
    );
  }

  // -------- getKardex (acepta number|string en posicional) --------
  async getKardex(params?: {
    materialIdInt?: number | string;
    almacenId?: string;
    limit?: number | string;
  }): Promise<any[]>;
  async getKardex(
    materialIdInt?: number | string,
    almacenId?: string,
    limit?: number | string,
    _unused?: any,
  ): Promise<any[]>;
  async getKardex(
    p1?: any,
    p2?: any,
    p3?: any,
    _p4?: any,
  ): Promise<any[]> {
    let materialId: number | undefined = undefined;
    let almacenId: string | undefined = undefined;
    let limit = 50;

    if (typeof p1 === 'object' && p1 !== null) {
      materialId =
        p1.materialIdInt !== undefined ? Number(p1.materialIdInt) : undefined;
      almacenId = p1.almacenId;
      limit = Math.max(1, Math.min(100, Number(p1.limit ?? 50)));
    } else {
      materialId = p1 !== undefined ? Number(p1) : undefined;
      almacenId = p2;
      limit = Math.max(1, Math.min(100, Number(p3 ?? 50)));
    }

    try {
      if (materialId && almacenId) {
        return await this.dataSource.query(
          `SELECT * FROM kardex WHERE material_id=$1 AND almacen_id=$2 ORDER BY created_at DESC LIMIT $3`,
          [materialId, almacenId, limit],
        );
      } else if (materialId) {
        return await this.dataSource.query(
          `SELECT * FROM kardex WHERE material_id=$1 ORDER BY created_at DESC LIMIT $2`,
          [materialId, limit],
        );
      }
      return await this.dataSource.query(
        `SELECT * FROM kardex ORDER BY created_at DESC LIMIT $1`,
        [limit],
      );
    } catch {
      if (materialId && almacenId) {
        return await this.dataSource.query(
          `
          SELECT
            m.id,
            m.tipo,
            m.almacen_origen_id,
            m.almacen_destino_id,
            m.material_id,
            m.cantidad,
            m.created_at
          FROM movimientos m
          WHERE m.material_id=$1
            AND (m.almacen_origen_id=$2 OR m.almacen_destino_id=$2)
          ORDER BY m.created_at DESC
          LIMIT $3
        `,
          [materialId, almacenId, limit],
        );
      } else if (materialId) {
        return await this.dataSource.query(
          `
          SELECT
            m.id,
            m.tipo,
            m.almacen_origen_id,
            m.almacen_destino_id,
            m.material_id,
            m.cantidad,
            m.created_at
          FROM movimientos m
          WHERE m.material_id=$1
          ORDER BY m.created_at DESC
          LIMIT $2
        `,
          [materialId, limit],
        );
      }
      return await this.dataSource.query(
        `
        SELECT
          m.id,
          m.tipo,
          m.almacen_origen_id,
          m.almacen_destino_id,
          m.material_id,
          m.cantidad,
          m.created_at
        FROM movimientos m
        ORDER BY m.created_at DESC
        LIMIT $1
      `,
        [limit],
      );
    }
  }

  // ================== NÚCLEO ==================

  async crearMovimiento(dto: CrearMovimientoDto, userId?: string) {
    const materialId =
      dto.materialIdInt ??
      (dto.materialId !== undefined ? Number(dto.materialId) : NaN);
    if (!Number.isInteger(materialId) || materialId <= 0) {
      throw new BadRequestException('materialIdInt/materialId inválido.');
    }

    const tipo = dto.tipo;
    if (!['ingreso', 'egreso', 'transferencia', 'ajuste'].includes(tipo)) {
      throw new BadRequestException('tipo inválido.');
    }

    const cantidad = Number(dto.cantidad ?? 0);
    const cantidadSigned =
      dto.cantidadSigned !== undefined
        ? Number(dto.cantidadSigned)
        : undefined;

    if (tipo === 'ingreso' && !dto.almacenDestinoId) {
      throw new BadRequestException('ingreso requiere almacenDestinoId');
    }
    if (tipo === 'egreso' && !dto.almacenOrigenId) {
      throw new BadRequestException('egreso requiere almacenOrigenId');
    }
    if (
      tipo === 'transferencia' &&
      (!dto.almacenOrigenId ||
        !dto.almacenDestinoId ||
        dto.almacenOrigenId === dto.almacenDestinoId)
    ) {
      throw new BadRequestException(
        'transferencia requiere almacenOrigenId != almacenDestinoId',
      );
    }
    if (tipo !== 'ajuste' && (!Number.isFinite(cantidad) || cantidad <= 0)) {
      throw new BadRequestException('cantidad > 0 requerida');
    }
    if (tipo === 'ajuste' && !Number.isFinite(cantidadSigned)) {
      throw new BadRequestException(
        'ajuste requiere cantidadSigned (puede ser negativa o positiva)',
      );
    }

    const qr = this.dataSource.createQueryRunner();
    await qr.connect();
    await qr.startTransaction('READ COMMITTED');

    // --- helpers con el runner (scoped a la tx) ---
    // USAR ÚNICAMENTE CANDADO ASESORIO; nada de LEFT JOIN ... FOR UPDATE
    const getStockForUpdate = async (almacenId: string): Promise<number> => {
      // candado por par almacén-material (coherente con upsertStock)
      await qr.query(
        `SELECT pg_advisory_xact_lock(hashtext($1));`,
        [`${almacenId}:${materialId}`],
      );
      const r = await qr.query(
        `SELECT COALESCE(cantidad,0)::bigint AS qty
         FROM stock_almacen
         WHERE almacen_id = $1 AND material_id = $2`,
        [almacenId, materialId],
      );
      return Number(r?.[0]?.qty ?? 0);
    };

    const ensureSaldoSuficiente = async (
      almacenId: string,
      req: number,
    ): Promise<void> => {
      const disp = await getStockForUpdate(almacenId);
      if (disp < req) {
        throw new ConflictException('saldo insuficiente');
      }
    };

    try {
      // Idempotencia
      if (dto.idempotencyKey) {
        const idem = await qr.query(
          `SELECT id FROM movimientos WHERE idempotency_key = $1`,
          [dto.idempotencyKey],
        );
        if (idem.length > 0) {
          await qr.commitTransaction();
          return { id: String(idem[0].id) };
        }
      }

      // Almacenes
      const almacenesIds = [dto.almacenOrigenId, dto.almacenDestinoId].filter(
        Boolean,
      ) as string[];
      let almacenesInfo: Record<
        string,
        { id: string; tipo: 'principal' | 'tecnico'; tecnico_id: string | null }
      > = {};
      if (almacenesIds.length > 0) {
        const rows = await qr.query(
          `SELECT id, tipo, tecnico_id FROM almacenes WHERE id = ANY($1::uuid[])`,
          [almacenesIds],
        );
        almacenesInfo = Object.fromEntries(
          rows.map((r: any) => [
            r.id,
            { id: r.id, tipo: r.tipo, tecnico_id: r.tecnico_id ?? null },
          ]),
        );
        for (const aid of almacenesIds) {
          if (!almacenesInfo[aid]) {
            throw new NotFoundException(`Almacén no encontrado: ${aid}`);
          }
        }
      }

      // Lock par (advisory por par almacén-material para reducir contención)
      const lockPair = async (almacenId: string) => {
        await qr.query(
          `SELECT pg_advisory_xact_lock(hashtext($1));`,
          [`${almacenId}:${materialId}`],
        );
      };

      // Upsert stock con control de saldo
      const upsertStock = async (almacenId: string, delta: number) => {
        await lockPair(almacenId);
        if (delta >= 0) {
          const upd = await qr.query(
            `
            UPDATE stock_almacen
            SET cantidad = cantidad + $3
            WHERE almacen_id = $1 AND material_id = $2
            RETURNING cantidad
            `,
            [almacenId, materialId, delta],
          );
          if (upd.length === 0) {
            await qr.query(
              `
              INSERT INTO stock_almacen (almacen_id, material_id, cantidad)
              VALUES ($1, $2, $3)
              `,
              [almacenId, materialId, delta],
            );
          }
        } else {
          const res = await qr.query(
            `
            UPDATE stock_almacen
            SET cantidad = cantidad + $3
            WHERE almacen_id = $1 AND material_id = $2 AND (cantidad + $3) >= 0
            RETURNING cantidad
            `,
            [almacenId, materialId, delta],
          );
          if (res.length === 0) {
            throw new ConflictException('saldo insuficiente');
          }
        }
      };

      // Sync inv_tecnico exacto
      const syncInvTecnicoExact = async (almacenId: string) => {
        const info = almacenesInfo[almacenId];
        if (!info || info.tipo !== 'tecnico' || !info.tecnico_id) return;

        const cur = await qr.query(
          `SELECT cantidad FROM stock_almacen WHERE almacen_id = $1 AND material_id = $2`,
          [almacenId, materialId],
        );
        const qty = cur.length > 0 ? Number(cur[0].cantidad ?? 0) : 0;

        await qr.query(
          `
          UPDATE inv_tecnico
          SET cantidad = $3
          WHERE tecnico_id = $1 AND material_id = $2
          `,
          [info.tecnico_id, materialId, qty],
        );
        await qr.query(
          `
          INSERT INTO inv_tecnico (tecnico_id, material_id, cantidad)
          SELECT $1, $2, $3
          WHERE NOT EXISTS (
            SELECT 1 FROM inv_tecnico WHERE tecnico_id=$1 AND material_id=$2
          )
        `,
          [info.tecnico_id, materialId, qty],
        );
      };

      // ---- PRECHECK de saldo (evita que se inserte movimiento si no alcanza) ----
      if (tipo === 'egreso') {
        await ensureSaldoSuficiente(dto.almacenOrigenId!, Number(cantidad));
      } else if (tipo === 'transferencia') {
        await ensureSaldoSuficiente(dto.almacenOrigenId!, Number(cantidad));
      } else if (tipo === 'ajuste' && Number(cantidadSigned) < 0) {
        const target = dto.almacenDestinoId ?? dto.almacenOrigenId;
        if (!target)
          throw new BadRequestException(
            'ajuste requiere almacenDestinoId o almacenOrigenId',
          );
        await ensureSaldoSuficiente(target, Math.abs(Number(cantidadSigned)));
      }

      // 1) Impacto de stock
      if (tipo === 'ingreso') {
        await upsertStock(dto.almacenDestinoId!, +Number(dto.cantidad));
      } else if (tipo === 'egreso') {
        await upsertStock(dto.almacenOrigenId!, -Number(dto.cantidad));
      } else if (tipo === 'transferencia') {
        await upsertStock(dto.almacenOrigenId!, -Number(dto.cantidad));
        await upsertStock(dto.almacenDestinoId!, +Number(dto.cantidad));
      } else if (tipo === 'ajuste') {
        const target = dto.almacenDestinoId ?? dto.almacenOrigenId;
        if (!target)
          throw new BadRequestException(
            'ajuste requiere almacenDestinoId o almacenOrigenId',
          );
        await upsertStock(target, Number(dto.cantidadSigned));
      }

      // 2) Movimiento
      let insertedId: string | undefined;
      try {
        const ins = await qr.query(
          `
          INSERT INTO movimientos (
            idempotency_key, tipo, almacen_origen_id, almacen_destino_id,
            material_id, cantidad, motivo, ref_externa, evidencia_key, usuario_op_id
          )
          VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
          RETURNING id
          `,
          [
            dto.idempotencyKey ?? `auto-${Date.now()}-${Math.random()}`,
            tipo,
            dto.almacenOrigenId ?? null,
            dto.almacenDestinoId ?? null,
            materialId,
            tipo === 'ajuste' ? Number(dto.cantidadSigned) : Number(dto.cantidad),
            dto.motivo ?? null,
            dto.refExterna ?? null,
            dto.evidenciaKey ?? null,
            userId ?? null,
          ],
        );
        insertedId = String(ins[0].id);
      } catch (e: any) {
        if (String(e?.code) === '23505' && dto.idempotencyKey) {
          const idem = await qr.query(
            `SELECT id FROM movimientos WHERE idempotency_key = $1`,
            [dto.idempotencyKey],
          );
          if (idem.length > 0) {
            insertedId = String(idem[0].id);
          } else {
            throw new ConflictException('Conflicto de idempotencia.');
          }
        } else {
          throw e;
        }
      }

      // 3) Espejo
      if (tipo === 'ingreso') {
        await syncInvTecnicoExact(dto.almacenDestinoId!);
      } else if (tipo === 'egreso') {
        await syncInvTecnicoExact(dto.almacenOrigenId!);
      } else if (tipo === 'transferencia') {
        await syncInvTecnicoExact(dto.almacenOrigenId!);
        await syncInvTecnicoExact(dto.almacenDestinoId!);
      } else if (tipo === 'ajuste') {
        const target = dto.almacenDestinoId ?? dto.almacenOrigenId!;
        await syncInvTecnicoExact(target);
      }

      await qr.commitTransaction();
      return { id: insertedId! };
    } catch (e) {
      await qr.rollbackTransaction();
      throw e;
    } finally {
      await qr.release();
    }
  }

  // =================== HELPERS ===================

  private async getAlmacenDeTecnico(tecnicoId: string): Promise<string | null> {
    const r = await this.dataSource.query(
      `
      SELECT id FROM almacenes
      WHERE tipo='tecnico' AND tecnico_id=$1
      LIMIT 1
    `,
      [tecnicoId],
    );
    return r?.[0]?.id ?? null;
  }
}
