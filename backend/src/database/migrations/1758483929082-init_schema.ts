import { MigrationInterface, QueryRunner } from 'typeorm';
export class InitSchema1758483929082 implements MigrationInterface {
  name = 'InitSchema1758483929082';
  public async up(qr: QueryRunner): Promise<void> {
    await qr.query(`ALTER TABLE IF EXISTS "usuarios" DROP CONSTRAINT IF EXISTS "usuarios_municipio_id_fkey"`);
    await qr.query(`ALTER TABLE IF EXISTS "usuarios" DROP CONSTRAINT IF EXISTS "usuarios_ciudad_id_fkey"`);
    await qr.query(`ALTER TABLE IF EXISTS "usuarios" DROP CONSTRAINT IF EXISTS "usuarios_barrio_id_fkey"`);
    await qr.query(`ALTER TABLE IF EXISTS "ordenes" DROP CONSTRAINT IF EXISTS "fk_orden_usuario"`);
    await qr.query(`ALTER TABLE IF EXISTS "ordenes" DROP CONSTRAINT IF EXISTS "fk_orden_venta"`);
    await qr.query(`ALTER TABLE IF EXISTS "ordenes" DROP CONSTRAINT IF EXISTS "fk_orden_tecnico"`);
    await qr.query(`ALTER TABLE IF EXISTS "ordenes" DROP CONSTRAINT IF EXISTS "fk_ordenes_tecnico"`);
    await qr.query(`ALTER TABLE IF EXISTS "ordenes" DROP CONSTRAINT IF EXISTS "fk_ordenes_ventas"`);
    await qr.query(`ALTER TABLE IF EXISTS "ordenes" DROP CONSTRAINT IF EXISTS "fk_ordenes_usuarios"`);
    await qr.query(`ALTER TABLE IF EXISTS public."evidencias" DROP CONSTRAINT IF EXISTS "fk_evidencias_ordenes"`);
  }
  public async down(_qr: QueryRunner): Promise<void> {}
}
