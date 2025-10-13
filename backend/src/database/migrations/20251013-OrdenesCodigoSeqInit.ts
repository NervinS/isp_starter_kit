// src/migrations/20251013-OrdenesCodigoSeqInit.ts
import { MigrationInterface, QueryRunner } from 'typeorm';

export class OrdenesCodigoSeqInit20251013 implements MigrationInterface {
  name = 'OrdenesCodigoSeqInit20251013';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // Crea la secuencia si no existe
    await queryRunner.query(`
      CREATE SEQUENCE IF NOT EXISTS public.ordenes_codigo_seq
      INCREMENT BY 1
      MINVALUE 1
      NO MAXVALUE
      START 1
      CACHE 1
    `);

    // Sincroniza el contador con los códigos existentes (COR-000123, REC-000456, etc.)
    await queryRunner.query(`
      SELECT setval(
        'public.ordenes_codigo_seq',
        COALESCE(
          (
            SELECT MAX((regexp_replace(codigo, '^[A-Z]+-', '')::bigint))
            FROM public.ordenes
          ),
          0
        )
      )
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    // Elimina la secuencia (no afecta la tabla ordenes)
    await queryRunner.query(`
      DROP SEQUENCE IF EXISTS public.ordenes_codigo_seq
    `);
  }
}
