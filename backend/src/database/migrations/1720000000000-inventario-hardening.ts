// src/database/migrations/1720000000000-inventario-hardening.ts
import { MigrationInterface, QueryRunner } from 'typeorm';

export class InventarioHardening1720000000000 implements MigrationInterface {
  name = 'InventarioHardening1720000000000';

  public async up(qr: QueryRunner): Promise<void> {
    await qr.query(`
      -- 1) Normalizar tipos 'transferencia' -> 'traslado' si quedara alguno
      UPDATE public.movimientos SET tipo='traslado' WHERE tipo='transferencia';
    `);

    await qr.query(`
      -- 2) Re-crear CHECK de tipos
      ALTER TABLE public.movimientos DROP CONSTRAINT IF EXISTS movimientos_tipo_check;
      ALTER TABLE public.movimientos
        ADD CONSTRAINT movimientos_tipo_check
        CHECK (tipo IN ('ingreso','egreso','ajuste','traslado'));
    `);

    await qr.query(`
      -- 3) No negativos en stock_almacen
      ALTER TABLE public.stock_almacen
        DROP CONSTRAINT IF EXISTS stock_almacen_cantidad_nonneg;
      ALTER TABLE public.stock_almacen
        ADD CONSTRAINT stock_almacen_cantidad_nonneg CHECK (cantidad >= 0);
    `);

    await qr.query(`
      -- 4) Índice único (por si faltara en algún entorno)
      CREATE UNIQUE INDEX IF NOT EXISTS ux_stock_almacen
      ON public.stock_almacen(almacen_id, material_id);
    `);
  }

  public async down(qr: QueryRunner): Promise<void> {
    await qr.query(`
      -- revertir índice/constraint; no intentamos des-normalizar datos
      DROP INDEX IF EXISTS ux_stock_almacen;
    `);
    await qr.query(`
      ALTER TABLE public.stock_almacen
        DROP CONSTRAINT IF EXISTS stock_almacen_cantidad_nonneg;
    `);
    await qr.query(`
      ALTER TABLE public.movimientos
        DROP CONSTRAINT IF EXISTS movimientos_tipo_check;
      -- Si quieres, podrías volver al check anterior:
      ALTER TABLE public.movimientos
        ADD CONSTRAINT movimientos_tipo_check
        CHECK (tipo IN ('ingreso','egreso','ajuste','traslado','transferencia'));
    `);
  }
}
