import { MigrationInterface, QueryRunner } from 'typeorm';

export class OrdenesCodigoSeqInit1760476797033 implements MigrationInterface {
  name = 'OrdenesCodigoSeqInit1760476797033';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // 1) Crear la secuencia si no existe
    await queryRunner.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relkind = 'S'
            AND n.nspname = 'public'
            AND c.relname = 'ordenes_codigo_seq'
        ) THEN
          CREATE SEQUENCE public.ordenes_codigo_seq
            INCREMENT BY 1
            START WITH 0
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;
        END IF;
      END
      $$;
    `);

    // 2) Posicionar la secuencia con el mayor número encontrado en public.ordenes.codigo
    //    - Extraemos solo dígitos con regexp_replace('[^0-9]', '', 'g')
    //    - Validamos con ~ '^[0-9]+$' antes de castear a bigint
    await queryRunner.query(`
      SELECT setval(
        'public.ordenes_codigo_seq',
        COALESCE(
          (
            SELECT MAX(val) FROM (
              SELECT
                CASE
                  WHEN regexp_replace(codigo, '[^0-9]', '', 'g') ~ '^[0-9]+$'
                    THEN (regexp_replace(codigo, '[^0-9]', '', 'g'))::bigint
                  ELSE NULL
                END AS val
              FROM public.ordenes
            ) t
          ),
          0
        )
      );
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    // No borramos la secuencia para no romper nada "verde".
    // En su lugar, la reseteamos si existe.
    await queryRunner.query(`
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relkind = 'S'
            AND n.nspname = 'public'
            AND c.relname = 'ordenes_codigo_seq'
        ) THEN
          ALTER SEQUENCE public.ordenes_codigo_seq RESTART WITH 0;
        END IF;
      END
      $$;
    `);
  }
}
