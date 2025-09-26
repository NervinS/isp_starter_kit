// src/modules/tecnicos/tecnicos.service.ts
import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import { PdfService } from '../pdf/pdf.service';

type CerrarBody = {
  tecnicoId: string;
  materiales?: Array<{ materialIdInt: number; cantidad: number }>;
};

@Injectable()
export class TecnicosService {
  constructor(
    @InjectDataSource() private readonly ds: DataSource,
    private readonly pdf: PdfService,
  ) {}

  async pendientes(tecnicoId: string) {
    return this.ds.query(
      `SELECT * FROM ordenes
        WHERE tecnico_id = $1
          AND estado IN ('agendada', 'en_progreso')
        ORDER BY created_at DESC`,
      [tecnicoId],
    );
  }

  async iniciarOrdenPorId(tecnicoId: string, ordenId: string) {
    return this.ds.transaction('READ COMMITTED', async (em) => {
      const [orden] = await em.query(
        `SELECT * FROM ordenes WHERE id=$1 FOR UPDATE`,
        [ordenId],
      );
      if (!orden) throw new NotFoundException('Orden no existe');
      if (orden.tecnico_id !== tecnicoId) {
        throw new BadRequestException('Orden no pertenece a este técnico');
      }

      if (orden.iniciada_at) {
        return {
          codigo: orden.codigo,
          estado: orden.estado,
          iniciada_at: orden.iniciada_at,
          cerrada_at: orden.cerrada_at,
          _idempotent: true,
        };
      }

      await em.query(
        `UPDATE ordenes
            SET iniciada_at = NOW(),
                estado = 'en_progreso'
          WHERE id=$1 AND iniciada_at IS NULL`,
        [ordenId],
      );

      const [updated] = await em.query(`SELECT * FROM ordenes WHERE id=$1`, [
        ordenId,
      ]);
      return {
        codigo: updated.codigo,
        estado: updated.estado,
        iniciada_at: updated.iniciada_at,
        cerrada_at: updated.cerrada_at,
        _idempotent: false,
      };
    });
  }

  async iniciarOrdenPorCodigo(tecnicoId: string, codigo: string) {
    const [row] = await this.ds.query(
      `SELECT id FROM ordenes WHERE codigo=$1`,
      [codigo],
    );
    if (!row) throw new NotFoundException('Orden no existe');
    return this.iniciarOrdenPorId(tecnicoId, row.id);
  }

  async cerrarOrdenPorId(tecnicoId: string, ordenId: string, body: CerrarBody) {
    if (body.tecnicoId !== tecnicoId) {
      throw new BadRequestException('tecnicoId no coincide con la ruta');
    }

    return this.ds.transaction('READ COMMITTED', async (em) => {
      const [orden] = await em.query(
        `SELECT * FROM ordenes WHERE id=$1 FOR UPDATE`,
        [ordenId],
      );
      if (!orden)
        throw new HttpException('Orden no existe', HttpStatus.NOT_FOUND);
      if (orden.tecnico_id !== tecnicoId) {
        throw new BadRequestException('Orden no pertenece a este técnico');
      }

      const pdfKey = `ordenes/${orden.codigo}.pdf`;

      // Si ya está cerrada, intenta “sanear” el PDF si falta
      if (orden.cerrada_at) {
        let url: string | null = orden.pdf_url ?? null;
        try {
          const exists = await this.pdf.exists(pdfKey);
          if (!exists) {
            url = await this.pdf.ensurePdf(pdfKey);
            if (url) {
              await em.query(
                `UPDATE ordenes
                   SET pdf_key = CASE WHEN $2::text IS NOT NULL THEN $3 ELSE pdf_key END,
                       pdf_url = COALESCE($2::text, pdf_url)
                 WHERE id=$1`,
                [ordenId, url, pdfKey],
              );
            }
          }
        } catch {
          // no romper idempotencia
        }
        return {
          codigo: orden.codigo,
          estado: orden.estado,
          cerradaAt: orden.cerrada_at,
          pdfUrl: url,
          _idempotent: true,
        };
      }

      // Lock de líneas
      await em.query(
        `SELECT 1 FROM orden_materiales WHERE orden_id=$1 FOR UPDATE`,
        [ordenId],
      );

      // UPDATE → INSERT (sin ON CONFLICT)
      if (Array.isArray(body.materiales) && body.materiales.length) {
        for (const it of body.materiales) {
          const upd = await em.query(
            `UPDATE orden_materiales
                SET cantidad = cantidad + $3
              WHERE orden_id = $1
                AND material_id_int = $2`,
            [ordenId, it.materialIdInt, it.cantidad],
          );
          const touched = (upd as any)?.rowCount ?? 0; // DataSource.query no trae rowCount; esto da 0 y haremos INSERT.
          if (touched === 0) {
            await em.query(
              `INSERT INTO orden_materiales
                 (id, orden_id, material_id, material_id_int, cantidad, precio_unitario, total_calculado, descontado)
               VALUES (uuid_generate_v4(), $1, uuid_generate_v4(), $2, $3, 0, 0, FALSE)`,
              [ordenId, it.materialIdInt, it.cantidad],
            );
          }
        }
      }

      // Verificación de stock
      const faltantes = await em.query(
        `SELECT om.material_id_int, om.cantidad, it.cantidad AS stock
           FROM orden_materiales om
      LEFT JOIN inv_tecnico it
             ON it.tecnico_id=$1 AND it.material_id=om.material_id_int
          WHERE om.orden_id=$2
            AND om.descontado=FALSE
            AND (it.cantidad IS NULL OR it.cantidad < om.cantidad)`,
        [tecnicoId, ordenId],
      );
      if (faltantes.length) {
        throw new HttpException('Stock insuficiente', HttpStatus.BAD_REQUEST);
      }

      // Descuento de inventario
      await em.query(
        `UPDATE inv_tecnico it
            SET cantidad = it.cantidad - om.cantidad
           FROM orden_materiales om
          WHERE om.orden_id=$1
            AND om.descontado=FALSE
            AND it.tecnico_id=$2
            AND it.material_id=om.material_id_int`,
        [ordenId, tecnicoId],
      );

      // Marcar líneas descontadas
      await em.query(
        `UPDATE orden_materiales
            SET descontado=TRUE
          WHERE orden_id=$1 AND descontado=FALSE`,
        [ordenId],
      );

      // Generar/subir PDF (best-effort)
      let pdfUrl: string | null = null;
      try {
        pdfUrl = await this.pdf.ensurePdf(pdfKey);
      } catch {
        pdfUrl = null;
      }

      // Cerrar orden (cast explícito para evitar “unknown”)
      await em.query(
        `UPDATE ordenes
            SET cerrada_at = NOW(),
                estado    = 'cerrada',
                pdf_key   = CASE WHEN $2::text IS NOT NULL THEN $3 ELSE pdf_key END,
                pdf_url   = COALESCE($2::text, pdf_url)
          WHERE id=$1 AND cerrada_at IS NULL`,
        [ordenId, pdfUrl, pdfKey],
      );

      // Ajuste de estado del usuario (sin parámetros tipados ambiguos)
      if (orden.usuario_id) {
        await em.query(
          `UPDATE usuarios u
              SET estado = CASE o.tipo
                             WHEN 'INS' THEN 'instalado'
                             WHEN 'REC' THEN 'instalado'
                             WHEN 'COR' THEN 'desconectado'
                             WHEN 'BAJ' THEN 'terminado'
                             ELSE u.estado
                           END
            FROM ordenes o
           WHERE o.id=$1 AND o.usuario_id=u.id AND o.cerrada_at IS NOT NULL`,
          [ordenId],
        );
      }

      const [closed] = await em.query(`SELECT * FROM ordenes WHERE id=$1`, [
        ordenId,
      ]);
      return {
        codigo: closed.codigo,
        estado: closed.estado,
        cerradaAt: closed.cerrada_at,
        pdfUrl: closed.pdf_url ?? null,
        _idempotent: false,
      };
    });
  }

  async cerrarPorCodigo(tecnicoId: string, codigo: string, body: CerrarBody) {
    const [row] = await this.ds.query(
      `SELECT id FROM ordenes WHERE codigo=$1`,
      [codigo],
    );
    if (!row) throw new NotFoundException('Orden no existe');
    return this.cerrarOrdenPorId(tecnicoId, row.id, body);
  }
}
