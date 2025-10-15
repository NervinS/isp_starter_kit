import { MigrationInterface, QueryRunner } from 'typeorm';

export class InitSchema1758484018068 implements MigrationInterface {
  name = 'InitSchema1758484018068';

  public async up(qr: QueryRunner): Promise<void> {
    await qr.query(`
      CREATE TABLE IF NOT EXISTS public.municipios (
        id uuid NOT NULL DEFAULT uuid_generate_v4(),
        codigo text NOT NULL,
        nombre text NOT NULL,
        activo boolean NOT NULL DEFAULT true,
        CONSTRAINT pk_municipios PRIMARY KEY (id)
      );
    `);
    await qr.query(`CREATE INDEX IF NOT EXISTS idx_municipios_codigo ON public.municipios (codigo);`);
    await qr.query(`CREATE INDEX IF NOT EXISTS idx_municipios_nombre ON public.municipios (nombre);`);
    await qr.query(`CREATE UNIQUE INDEX IF NOT EXISTS ux_municipios_codigo ON public.municipios (codigo);`);
    await qr.query(`CREATE UNIQUE INDEX IF NOT EXISTS ux_municipios_nombre ON public.municipios (nombre);`);

    await qr.query(`
      CREATE TABLE IF NOT EXISTS public.vias (
        id uuid NOT NULL DEFAULT uuid_generate_v4(),
        codigo text NOT NULL,
        nombre text NOT NULL,
        activo boolean NOT NULL DEFAULT true,
        CONSTRAINT pk_vias PRIMARY KEY (id)
      );
    `);
    await qr.query(`CREATE INDEX IF NOT EXISTS idx_vias_codigo ON public.vias (codigo);`);
    await qr.query(`CREATE INDEX IF NOT EXISTS idx_vias_nombre ON public.vias (nombre);`);
    await qr.query(`CREATE UNIQUE INDEX IF NOT EXISTS ux_vias_codigo ON public.vias (codigo);`);

    await qr.query(`
      CREATE TABLE IF NOT EXISTS public.sectores (
        id uuid NOT NULL DEFAULT uuid_generate_v4(),
        municipio_codigo text NOT NULL,
        zona text,
        nombre text NOT NULL,
        activo boolean NOT NULL DEFAULT true,
        CONSTRAINT pk_sectores PRIMARY KEY (id)
      );
    `);
    await qr.query(`CREATE INDEX IF NOT EXISTS idx_sectores_municipio_codigo ON public.sectores (municipio_codigo);`);
    await qr.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS ux_sectores_mun_zona_nombre
      ON public.sectores (municipio_codigo, zona, nombre);
    `);
    await qr.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_constraint c
          JOIN pg_class t ON t.oid = c.conrelid
          WHERE t.relname = 'sectores'
            AND c.conname = 'sectores_municipio_codigo_fkey'
        ) THEN
          ALTER TABLE public.sectores
          ADD CONSTRAINT sectores_municipio_codigo_fkey
          FOREIGN KEY (municipio_codigo)
          REFERENCES public.municipios(codigo)
          ON UPDATE CASCADE
          ON DELETE NO ACTION;
        END IF;
      END
      $$;
    `);
  }

  public async down(qr: QueryRunner): Promise<void> {
    await qr.query(`ALTER TABLE IF EXISTS public.sectores DROP CONSTRAINT IF EXISTS sectores_municipio_codigo_fkey;`);
    await qr.query(`DROP TABLE IF EXISTS public.sectores;`);
    await qr.query(`DROP TABLE IF EXISTS public.vias;`);
    await qr.query(`DROP TABLE IF EXISTS public.municipios;`);
  }
}
