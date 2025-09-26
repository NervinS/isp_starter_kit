// src/modules/ordenes/ordenes.service.ts
import { Injectable, HttpException, HttpStatus } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Injectable()
export class OrdenesService {
  constructor(private readonly ds: DataSource) {}

  /**
   * Cierre administrativo completo por CÓDIGO.
   * Reglas:
   *  - MAN no afecta el estado del usuario (ni estado_conexion).
   *  - REC cambia estado_conexion del usuario a 'conectado' y mantiene estado 'instalado'.
   * Idempotencia: si la orden ya está cerrada, no reprocesa; devuelve payload con _idempotent=true.
   */
  async cerrarCompletoAdmin(codigo: string, body: { tecnicoId?: string }) {
    return this.ds.transaction('READ COMMITTED', async (em) => {
      // 1) Lock de la orden por código
      const [orden] = await em.query(
        `SELECT * FROM ordenes WHERE codigo=$1 FOR UPDATE`,
        [codigo],
      );
      if (!orden) {
        throw new HttpException('Orden no existe', HttpStatus.NOT_FOUND);
      }

      // 2) Idempotencia
      if (orden.cerrada_at) {
        return {
          codigo: orden.codigo,
          estado: orden.estado,
          cerradaAt: orden.cerrada_at,
          pdfUrl: orden.pdf_url ?? null,
          _idempotent: true,
        };
      }

      // (Opcional) Validaciones adicionales (p.ej. pertenencia del técnico)
      // if (body?.tecnicoId && orden.tecnico_id && orden.tecnico_id !== body.tecnicoId) {
      //   throw new HttpException('La orden no pertenece al técnico indicado', HttpStatus.BAD_REQUEST);
      // }

      // 3) (Si aplicas materiales aquí, hazlo antes del cierre)

      // 4) Marcar orden cerrada
      await em.query(
        `UPDATE ordenes
           SET estado='cerrada',
               cerrada_at = now()
         WHERE id=$1`,
        [orden.id],
      );

      // 5) Efectos en usuario según tipo
      //    - MAN: no tocar usuario.
      //    - INS/REC/COR/BAJ: mantener mapeo de "estado".
      //    - REC: adicionalmente, conectar (estado_conexion='conectado').
      if (orden.usuario_id) {
        if (['INS', 'REC', 'COR', 'BAJ'].includes(orden.tipo)) {
          await em.query(
            `UPDATE usuarios u
                SET estado = CASE $2
                               WHEN 'INS' THEN 'instalado'
                               WHEN 'REC' THEN 'instalado'
                               WHEN 'COR' THEN 'desconectado'
                               WHEN 'BAJ' THEN 'terminado'
                               ELSE u.estado
                             END,
                    updated_at = now()
              WHERE u.id=$1`,
            [orden.usuario_id, orden.tipo],
          );
        }

        if (orden.tipo === 'REC') {
          await em.query(
            `UPDATE usuarios
                SET estado_conexion = 'conectado',
                    updated_at = now()
              WHERE id = $1`,
            [orden.usuario_id],
          );
        }
        // MAN: sin cambios
      }

      // 6) (Re)generación de PDF si aplica (conserva tu lógica existente)

      // 7) Payload final
      const [after] = await em.query(
        `SELECT codigo, estado, cerrada_at, pdf_url FROM ordenes WHERE id=$1`,
        [orden.id],
      );

      return {
        codigo: after.codigo,
        estado: after.estado,
        cerradaAt: after.cerrada_at,
        pdfUrl: after.pdf_url ?? null,
        _idempotent: false,
      };
    });
  }
}
