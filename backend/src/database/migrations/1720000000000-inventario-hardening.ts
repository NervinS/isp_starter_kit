// src/database/migrations/1720000000000-inventario-hardening.ts
import { MigrationInterface, QueryRunner } from 'typeorm';

export class InventarioHardening1720000000000 implements MigrationInterface {
  name = 'InventarioHardening1720000000000';

  public async up(qr: QueryRunner): Promise<void> {
    // 1) Normalización y CHECK SOLO si la columna "tipo" existe en inventario_movimientos
    await qr.query(`
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_schema='public'
            AND table_name='inventario_movimientos'
            AND column_name='tipo'
        ) THEN
          -- si existiera un histórico con 'transferencia', normalizar a 'traslado'
          UPDATE public.inventario_movimientos
          SET tipo='traslado'
          WHERE tipo='transferencia';

          -- recrear CHECK de tipos
          ALTER TABLE public.inventario_movimientos
            DROP CONSTRAINT IF EXISTS movimientos_tipo_check;

          ALTER TABLE public.inventario_movimientos
            ADD CONSTRAINT movimientos_tipo_check
            CHECK (tipo IN ('ingreso','egreso','ajuste','traslado'));
        END IF;
      END
      $$;
    `);

    // 2) No negativos en stock_almacen (idempotente)
    await qr.query(`
      ALTER TABLE public.stock_almacen
        DROP CONSTRAINT IF EXISTS stock_almacen_cantidad_nonneg;
    `);
    await qr.query(`
      ALTER TABLE public.stock_almacen
        ADD CONSTRAINT stock_almacen_cantidad_nonneg CHECK (cantidad >= 0);
    `);

    // 3) Índice único por (almacen_id, material_id) (idempotente)
    await qr.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS ux_stock_almacen
      ON public.stock_almacen(almacen_id, material_id);
    `);
  }

  public async down(qr: QueryRunner): Promise<void> {
    // revertir índice/constraint; sin tocar datos ni otras tablas
    await qr.query(`DROP INDEX IF EXISTS ux_stock_almacen;`);
    await qr.query(`
      ALTER TABLE public.stock_almacen
        DROP CONSTRAINT IF EXISTS stock_almacen_cantidad_nonneg;
    `);

    // Re-abrir el CHECK viejo solo si la columna existe
    await qr.query(`
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_schema='public'
            AND table_name='inventario_movimientos'
            AND column_name='tipo'
        ) THEN
          ALTER TABLE public.inventario_movimientos
            DROP CONSTRAINT IF EXISTS movimientos_tipo_check;

          ALTER TABLE public.inventario_movimientos
            ADD CONSTRAINT movimientos_tipo_check
            CHECK (tipo IN ('ingreso','egreso','ajuste','traslado','transferencia'));
        END IF;
      END
      $$;
    `);
  }
}
