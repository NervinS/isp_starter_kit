import {
  Body,
  Controller,
  Headers,
  HttpCode,
  HttpException,
  HttpStatus,
  Param,
  Post,
} from '@nestjs/common';
import { DataSource } from 'typeorm';
import { CerrarOrdenDto } from '../dto/cerrar-orden.dto';

function publicUrlFor(key: string | null): string | null {
  const base = process.env.MINIO_EXTERNAL_URL; // ej: http://127.0.0.1:9000
  if (!base || !key) return null;
  return `${base.replace(/\/+$/, '')}/evidencias/${key}`;
}

@Controller('tecnicos/:tecId/ordenes')
export class TecnicosCierreController {
  constructor(private readonly ds: DataSource) {}

  @Post(':ordenId/cerrar')
  @HttpCode(200)
  async cerrarOrden(
    @Param('tecId') tecId: string,
    @Param('ordenId') ordenId: string,
    @Body() body: CerrarOrdenDto,
    @Headers('x-idempotency-key') _idem?: string,
  ) {
    if (body.tecnicoId !== tecId) {
      throw new HttpException('tecnicoId no coincide con la ruta', HttpStatus.BAD_REQUEST);
    }

    const res = await this.ds.transaction('READ COMMITTED', async (em) => {
      // 1) Lock de orden
      const [orden] = await em.query(`SELECT * FROM ordenes WHERE id=$1 FOR UPDATE`, [ordenId]);
      if (!orden) throw new HttpException('Orden no existe', HttpStatus.NOT_FOUND);

      // 2) Idempotente
      if (orden.cerrada_at) {
        return {
          codigo: orden.codigo,
          estado: orden.estado,
          cerradaAt: orden.cerrada_at,
          pdfUrl: orden.pdf_url ?? null,
          _idempotent: true,
        };
      }

      // 3) Lock líneas
      await em.query(`SELECT 1 FROM orden_materiales WHERE orden_id=$1 FOR UPDATE`, [ordenId]);

      // 4) Verificación de stock (pendientes)
      const faltantes = await em.query(
        `SELECT om.material_id_int, om.cantidad, it.cantidad AS stock
           FROM orden_materiales om
      LEFT JOIN inv_tecnico it
             ON it.tecnico_id=$1 AND it.material_id=om.material_id_int
          WHERE om.orden_id=$2
            AND om.descontado=FALSE
            AND (it.cantidad IS NULL OR it.cantidad < om.cantidad)`,
        [tecId, ordenId],
      );
      if (faltantes.length) {
        throw new HttpException('Stock insuficiente', HttpStatus.BAD_REQUEST);
      }

      // 5) Descuento inventario
      await em.query(
        `UPDATE inv_tecnico it
            SET cantidad = it.cantidad - om.cantidad
           FROM orden_materiales om
          WHERE om.orden_id=$1
            AND om.descontado=FALSE
            AND it.tecnico_id=$2
            AND it.material_id = om.material_id_int`,
        [ordenId, tecId],
      );

      // 6) Flag líneas
      await em.query(
        `UPDATE orden_materiales SET descontado=TRUE WHERE orden_id=$1 AND descontado=FALSE`,
        [ordenId],
      );

      // 7) PDF (key y URL pública)
      const pdfKey = `cierre_${orden.codigo}.pdf`;
      const pdfUrl = publicUrlFor(pdfKey);

      // 8) Cierre
      await em.query(
        `UPDATE ordenes
            SET cerrada_at = NOW(),
                estado = 'cerrada',
                pdf_key = $2,
                pdf_url = $3
          WHERE id=$1 AND cerrada_at IS NULL`,
        [ordenId, pdfKey, pdfUrl],
      );

      // 9) Estado de usuario (si hay vínculo)
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

      // 10) Respuesta final
      const [after] = await em.query(
        `SELECT codigo, estado, cerrada_at, pdf_url FROM ordenes WHERE id=$1`,
        [ordenId],
      );
      return {
        codigo: after.codigo,
        estado: after.estado,
        cerradaAt: after.cerrada_at,
        pdfUrl: after.pdf_url ?? null,
        _idempotent: false,
      };
    });

    return res;
  }
}
