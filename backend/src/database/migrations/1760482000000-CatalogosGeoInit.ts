// src/database/migrations/1760482000000-CatalogosGeoInit.ts
import { MigrationInterface, QueryRunner } from 'typeorm';

export class CatalogosGeoInit1760482000000 implements MigrationInterface {
  name = 'CatalogosGeoInit1760482000000';

  public async up(qr: QueryRunner): Promise<void> {
    // municipales
    await qr.query(`
      CREATE TABLE IF NOT EXISTS public.municipios (
        id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
        codigo text NOT NULL UNIQUE,
        nombre text NOT NULL UNIQUE,
        activo boolean NOT NULL DEFAULT true
      );
    `);

    // vías
    await qr.query(`
      CREATE TABLE IF NOT EXISTS public.vias (
        id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
        codigo text NOT NULL UNIQUE,
        nombre text NOT NULL,
        activo boolean NOT NULL DEFAULT true
      );
    `);
    await qr.query(`CREATE INDEX IF NOT EXISTS idx_vias_nombre ON public.vias(nombre);`);

    // sectores (FK lógica por codigo de municipio)
    await qr.query(`
      CREATE TABLE IF NOT EXISTS public.sectores (
        id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
        municipio_codigo text NOT NULL,
        zona text,
        nombre text NOT NULL,
        activo boolean NOT NULL DEFAULT true
      );
    `);

    // Unique (municipio_codigo, zona, nombre)
    await qr.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'uniq_sectores_mun_zona_nombre'
        ) THEN
          ALTER TABLE public.sectores
            ADD CONSTRAINT uniq_sectores_mun_zona_nombre
            UNIQUE (municipio_codigo, zona, nombre);
        END IF;
      END
      $$;
    `);

    // FK sectores.municipio_codigo → municipios.codigo (ON UPDATE CASCADE)
    await qr.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'sectores_municipio_codigo_fkey'
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

    // Índices de apoyo
    await qr.query(`CREATE INDEX IF NOT EXISTS idx_municipios_codigo ON public.municipios(codigo);`);
    await qr.query(`CREATE INDEX IF NOT EXISTS idx_municipios_nombre ON public.municipios(nombre);`);
    await qr.query(`CREATE INDEX IF NOT EXISTS idx_sectores_municipio_codigo ON public.sectores(municipio_codigo);`);
  }

  public async down(qr: QueryRunner): Promise<void> {
    // Baja inversa y segura: primero FK y tabla dependiente
    await qr.query(`
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sectores_municipio_codigo_fkey') THEN
          ALTER TABLE public.sectores DROP CONSTRAINT sectores_municipio_codigo_fkey;
        END IF;
      END
      $$;
    `);
    await qr.query(`DROP TABLE IF EXISTS public.sectores;`);
    await qr.query(`DROP INDEX IF EXISTS idx_vias_nombre;`);
    await qr.query(`DROP TABLE IF EXISTS public.vias;`);
    await qr.query(`DROP INDEX IF EXISTS idx_municipios_codigo;`);
    await qr.query(`DROP INDEX IF EXISTS idx_municipios_nombre;`);
    await qr.query(`DROP TABLE IF EXISTS public.municipios;`);
  }
}
