import { MigrationInterface, QueryRunner } from "typeorm";

export class CatalogosInit1760477093009 implements MigrationInterface {
  name = 'CatalogosInit1760477093009';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "municipios" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "codigo" text NOT NULL,
        "nombre" text NOT NULL,
        "activo" boolean NOT NULL DEFAULT true,
        CONSTRAINT "PK_municipios_id" PRIMARY KEY ("id")
      )
    `);
    await queryRunner.query(`CREATE UNIQUE INDEX IF NOT EXISTS "ux_municipios_codigo" ON "municipios" ("codigo")`);
    await queryRunner.query(`CREATE UNIQUE INDEX IF NOT EXISTS "ux_municipios_nombre" ON "municipios" ("nombre")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_municipios_codigo" ON "municipios" ("codigo")`);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "vias" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "codigo" text NOT NULL,
        "nombre" text NOT NULL,
        "activo" boolean NOT NULL DEFAULT true,
        CONSTRAINT "PK_vias_id" PRIMARY KEY ("id")
      )
    `);
    await queryRunner.query(`CREATE UNIQUE INDEX IF NOT EXISTS "ux_vias_codigo" ON "vias" ("codigo")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_vias_codigo" ON "vias" ("codigo")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_vias_nombre" ON "vias" ("nombre")`);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "sectores" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "municipio_codigo" text NOT NULL,
        "zona" text,
        "nombre" text NOT NULL,
        "activo" boolean NOT NULL DEFAULT true,
        CONSTRAINT "PK_sectores_id" PRIMARY KEY ("id")
      )
    `);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "idx_sectores_municipio_codigo" ON "sectores" ("municipio_codigo")`);
    await queryRunner.query(`
      DO $$
      BEGIN
        BEGIN
          ALTER TABLE "sectores"
            ADD CONSTRAINT "uniq_sectores_mun_zona_nombre"
            UNIQUE ("municipio_codigo","zona","nombre");
        EXCEPTION
          WHEN duplicate_object THEN NULL;
        END;
      END
      $$;
    `);
    await queryRunner.query(`
      DO $$
      BEGIN
        BEGIN
          ALTER TABLE "sectores"
            ADD CONSTRAINT "sectores_municipio_codigo_fkey"
            FOREIGN KEY ("municipio_codigo")
            REFERENCES "municipios"("codigo")
            ON UPDATE CASCADE
            ON DELETE NO ACTION;
        EXCEPTION
          WHEN duplicate_object THEN NULL;
        END;
      END
      $$;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sectores_municipio_codigo_fkey') THEN
          ALTER TABLE "sectores" DROP CONSTRAINT "sectores_municipio_codigo_fkey";
        END IF;
      END$$;
    `);
    await queryRunner.query(`
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uniq_sectores_mun_zona_nombre') THEN
          ALTER TABLE "sectores" DROP CONSTRAINT "uniq_sectores_mun_zona_nombre";
        END IF;
      END$$;
    `);
    await queryRunner.query(`DROP TABLE IF EXISTS "sectores"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "ux_vias_codigo"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_vias_codigo"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_vias_nombre"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "vias"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "ux_municipios_codigo"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "ux_municipios_nombre"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "idx_municipios_codigo"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "municipios"`);
  }
}
