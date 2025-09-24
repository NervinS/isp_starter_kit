import { Injectable, HttpException, HttpStatus } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Injectable()
export class OrdenesService {
  constructor(private readonly ds: DataSource) {}

  async cerrarCompletoAdmin(codigo: string, body: { tecnicoId: string }) {
    return this.ds.transaction('READ COMMITTED', async (em) => {
      const [orden] = await em.query(`SELECT * FROM ordenes WHERE codigo=$1 FOR UPDATE`, [codigo]);
      if (!orden) throw new HttpException('Orden no existe', HttpStatus.NOT_FOUND);

      if (orden.cerrada_at) {
        return { id: orden.id, codigo: orden.codigo, estado: orden.estado, pdf_url: orden.pdf_url ?? null };
      }

      // Lock líneas
      await em.query(`SELECT 1 FROM orden_materiales WHERE orden_id=$1 FOR UPDATE`, [orden.id]);

      // Validación stock
      const faltantes = await em.query(
        `SELECT om.material_id_int, om.cantidad, it.cantidad AS stock
           FROM orden_materiales om
      LEFT JOIN inv_tecnico it
             ON it.tecnico_id=$1 AND it.material_id=om.material_id_int
          WHERE om.orden_id=$2
            AND om.descontado=FALSE
            AND (it.cantidad IS NULL OR it.cantidad < om.cantidad)`,
        [body.tecnicoId, orden.id],
      );
      if (faltantes.length) throw new HttpException('Stock insuficiente', HttpStatus.BAD_REQUEST);

      // Descuento + flag
      await em.query(
        `UPDATE inv_tecnico it
            SET cantidad = it.cantidad - om.cantidad
           FROM orden_materiales om
          WHERE om.orden_id=$1
            AND om.descontado=FALSE
            AND it.tecnico_id=$2
            AND it.material_id=om.material_id_int`,
        [orden.id, body.tecnicoId],
      );
      await em.query(
        `UPDATE orden_materiales SET descontado=TRUE WHERE orden_id=$1 AND descontado=FALSE`,
        [orden.id],
      );

      // Cierre + PDF url pública (bucket evidencias ya público)
      const pdfKey = `cierre_${orden.codigo}.pdf`;
      const pdfUrl = process.env.MINIO_EXTERNAL_URL
        ? `${process.env.MINIO_EXTERNAL_URL.replace(/\/+$/,'')}/evidencias/${pdfKey}`
        : null;

      await em.query(
        `UPDATE ordenes SET cerrada_at=NOW(), estado='cerrada', pdf_key=$2, pdf_url=$3 WHERE id=$1 AND cerrada_at IS NULL`,
        [orden.id, pdfKey, pdfUrl],
      );

      if (orden.usuario_id) {
        await em.query(
          `UPDATE usuarios u
              SET estado = CASE $2
                WHEN 'INS' THEN 'instalado'
                WHEN 'REC' THEN 'instalado'
                WHEN 'COR' THEN 'desconectado'
                WHEN 'BAJ' THEN 'terminado'
                ELSE u.estado
              END
            WHERE u.id=$1`,
          [orden.usuario_id, orden.tipo],
        );
      }

      const [after] = await em.query(`SELECT id, codigo, estado, pdf_url FROM ordenes WHERE id=$1`, [orden.id]);
      return after;
    });
  }
}
