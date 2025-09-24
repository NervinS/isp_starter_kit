// src/modules/inventario/inventario.service.ts
import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, QueryRunner } from 'typeorm';
import { Tecnico } from '../tecnicos/tecnico.entity';
import { Material } from '../materiales/material.entity';

type StockDto = {
  materialId: number;
  codigo: string;
  nombre: string;
  cantidad: number;
};

@Injectable()
export class InventarioService {
  constructor(
    private readonly dataSource: DataSource,
    @InjectRepository(Material)
    private readonly materialRepo: Repository<Material>,
    @InjectRepository(Tecnico)
    private readonly tecnicoRepo: Repository<Tecnico>,
  ) {}

  /**
   * Alias público que el controller expone por compatibilidad.
   * Lista el stock del técnico por material.
   */
  async listarStockDeTecnico(tecnicoId: string): Promise<StockDto[]> {
    return this.getStock(tecnicoId);
  }

  /**
   * Implementación base de listado de stock por técnico.
   * Usa SQL directo para evitar desalineaciones de tipos con entidades duplicadas.
   */
  async getStock(tecnicoId: string): Promise<StockDto[]> {
    // Verificar existencia del técnico (fail-fast)
    const existeTec = await this.tecnicoRepo.exist({ where: { id: tecnicoId } });
    if (!existeTec) throw new NotFoundException('Técnico no encontrado.');

    // Solo materiales que el técnico realmente tiene en inv_tecnico
    const filas: Array<{ materialId: number; codigo: string; nombre: string; cantidad: string | number | null }> =
      await this.dataSource.query(
        `
        SELECT
          it.material_id    AS "materialId",
          m.codigo          AS "codigo",
          m.nombre          AS "nombre",
          it.cantidad       AS "cantidad"
        FROM inv_tecnico it
        JOIN materiales m ON m.id = it.material_id
        WHERE it.tecnico_id = $1
        ORDER BY m.codigo ASC
        `,
        [tecnicoId],
      );

    return filas.map((r) => ({
      materialId: Number(r.materialId),
      codigo: r.codigo,
      nombre: r.nombre,
      cantidad: Number(r.cantidad ?? 0),
    }));
  }

  /**
   * Descontar stock del técnico (transacción, SELECT ... FOR UPDATE).
   * Lanza 400 si no hay stock suficiente o el material no está asociado a ese técnico.
   */
  async descontarStock(
    tecnicoId: string,
    materialId: number,
    cantidad: number,
  ): Promise<{ tecnicoId: string; materialId: number; cantidadAnterior: number; cantidadNueva: number }> {
    if (cantidad <= 0 || !Number.isInteger(cantidad)) {
      throw new BadRequestException('cantidad debe ser un entero positivo.');
    }

    // Validaciones de existencia
    const [tec, mat] = await Promise.all([
      this.tecnicoRepo.findOne({ where: { id: tecnicoId } }),
      this.materialRepo.findOne({ where: { id: materialId } }),
    ]);
    if (!tec) throw new NotFoundException('Técnico no encontrado.');
    if (!mat) throw new NotFoundException('Material no encontrado.');

    let qr: QueryRunner | null = null;
    try {
      qr = this.dataSource.createQueryRunner();
      await qr.connect();
      await qr.startTransaction('READ COMMITTED');

      // Bloquea el renglón de stock del técnico y el material
      const row = await qr.query(
        `
        SELECT cantidad
        FROM inv_tecnico
        WHERE tecnico_id = $1 AND material_id = $2
        FOR UPDATE
        `,
        [tecnicoId, materialId],
      );

      if (row.length === 0) {
        throw new BadRequestException('El técnico no tiene stock del material indicado.');
      }

      const actual = Number(row[0].cantidad ?? 0);
      if (actual < cantidad) {
        throw new BadRequestException(`Stock insuficiente: actual=${actual}, solicitado=${cantidad}`);
      }

      await qr.query(
        `
        UPDATE inv_tecnico
        SET cantidad = cantidad - $3
        WHERE tecnico_id = $1 AND material_id = $2
        `,
        [tecnicoId, materialId, cantidad],
      );

      await qr.commitTransaction();

      return {
        tecnicoId,
        materialId,
        cantidadAnterior: actual,
        cantidadNueva: actual - cantidad,
      };
    } catch (e) {
      if (qr && qr.isTransactionActive) {
        await qr.rollbackTransaction();
      }
      throw e;
    } finally {
      if (qr) await qr.release();
    }
  }

  /**
   * (Opcional) Aumentar stock — útil si más adelante agregas endpoints de ingreso.
   */
  async agregarStock(
    tecnicoId: string,
    materialId: number,
    cantidad: number,
  ): Promise<void> {
    if (cantidad <= 0 || !Number.isInteger(cantidad)) {
      throw new BadRequestException('cantidad debe ser un entero positivo.');
    }

    // Validar existencia
    const [tec, mat] = await Promise.all([
      this.tecnicoRepo.findOne({ where: { id: tecnicoId } }),
      this.materialRepo.findOne({ where: { id: materialId } }),
    ]);
    if (!tec) throw new NotFoundException('Técnico no encontrado.');
    if (!mat) throw new NotFoundException('Material no encontrado.');

    let qr: QueryRunner | null = null;
    try {
      qr = this.dataSource.createQueryRunner();
      await qr.connect();
      await qr.startTransaction('READ COMMITTED');

      // Intenta bloquear renglón si existe
      const row = await qr.query(
        `
        SELECT cantidad
        FROM inv_tecnico
        WHERE tecnico_id = $1 AND material_id = $2
        FOR UPDATE
        `,
        [tecnicoId, materialId],
      );

      if (row.length === 0) {
        // Inserta nuevo renglón
        await qr.query(
          `
          INSERT INTO inv_tecnico (tecnico_id, material_id, cantidad)
          VALUES ($1, $2, $3)
          `,
          [tecnicoId, materialId, cantidad],
        );
      } else {
        // Suma cantidad
        await qr.query(
          `
          UPDATE inv_tecnico
          SET cantidad = cantidad + $3
          WHERE tecnico_id = $1 AND material_id = $2
          `,
          [tecnicoId, materialId, cantidad],
        );
      }

      await qr.commitTransaction();
    } catch (e) {
      if (qr && qr.isTransactionActive) {
        await qr.rollbackTransaction();
      }
      throw e;
    } finally {
      if (qr) await qr.release();
    }
  }

  /**
   * (Opcional) Ajuste directo de stock — establece la cantidad exacta.
   */
  async ajustarStock(
    tecnicoId: string,
    materialId: number,
    cantidad: number,
  ): Promise<void> {
    if (cantidad < 0 || !Number.isInteger(cantidad)) {
      throw new BadRequestException('cantidad debe ser un entero mayor o igual a 0.');
    }

    // Validar existencia
    const [tec, mat] = await Promise.all([
      this.tecnicoRepo.findOne({ where: { id: tecnicoId } }),
      this.materialRepo.findOne({ where: { id: materialId } }),
    ]);
    if (!tec) throw new NotFoundException('Técnico no encontrado.');
    if (!mat) throw new NotFoundException('Material no encontrado.');

    let qr: QueryRunner | null = null;
    try {
      qr = this.dataSource.createQueryRunner();
      await qr.connect();
      await qr.startTransaction('READ COMMITTED');

      // Bloquea si existe
      const row = await qr.query(
        `
        SELECT cantidad
        FROM inv_tecnico
        WHERE tecnico_id = $1 AND material_id = $2
        FOR UPDATE
        `,
        [tecnicoId, materialId],
      );

      if (row.length === 0) {
        await qr.query(
          `
          INSERT INTO inv_tecnico (tecnico_id, material_id, cantidad)
          VALUES ($1, $2, $3)
          `,
          [tecnicoId, materialId, cantidad],
        );
      } else {
        await qr.query(
          `
          UPDATE inv_tecnico
          SET cantidad = $3
          WHERE tecnico_id = $1 AND material_id = $2
          `,
          [tecnicoId, materialId, cantidad],
        );
      }

      await qr.commitTransaction();
    } catch (e) {
      if (qr && qr.isTransactionActive) {
        await qr.rollbackTransaction();
      }
      throw e;
    } finally {
      if (qr) await qr.release();
    }
  }
}
