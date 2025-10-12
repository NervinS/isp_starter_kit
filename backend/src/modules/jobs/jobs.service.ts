// src/modules/jobs/jobs.service.ts
import { Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';

type TipoSim = 'COR' | 'REC';

@Injectable()
export class JobsService {
  constructor(private readonly ds: DataSource) {}

  async simular(tipo: TipoSim, fechaISO?: string) {
    const fecha = fechaISO ? new Date(fechaISO) : new Date();

    // Si usuarios.id es integer en tu DB, tipa como number
    const usuarios: Array<{ id: number }> = await this.ds.query(
      `SELECT id FROM usuarios ORDER BY id LIMIT 5`,
    );

    const detalle: Array<{ codigo: string; tipo: TipoSim; usuarioId: number }> = [];

    for (const u of usuarios) {
      const r = await this.ds.transaction('READ COMMITTED', async (em) => {
        const code = `${tipo}-${Math.floor(Date.now() / 1000)}`;

        // ⚠️ No seteamos "id"; lo genera la DB (serial/identity)
        const [ins] = await em.query(
          `INSERT INTO ordenes (
             codigo, estado, tecnico_id, tipo, subtotal, total, usuario_id, created_at, updated_at
           )
           VALUES (
             $1, 'agendada', NULL, $2, 0, 0, $3, now(), now()
           )
           RETURNING id, codigo`,
          [code, tipo, u.id],
        );

        // Cerrar inmediatamente la orden creada
        await em.query(
          `UPDATE ordenes
             SET cerrada_at = NOW(), estado = 'cerrada'
           WHERE id = $1 AND cerrada_at IS NULL`,
          [ins.id],
        );

        // Cambiar estado del usuario según el tipo
        const nuevo =
          tipo === 'COR' ? 'desconectado'
          : tipo === 'REC' ? 'instalado'
          : null;

        if (nuevo) {
          await em.query(
            `UPDATE usuarios SET estado = $2 WHERE id = $1`,
            [u.id, nuevo],
          );
        }

        return { codigo: ins.codigo as string, tipo, usuarioId: u.id };
      });

      detalle.push(r);
    }

    return {
      ok: true,
      tipo,
      fecha: fecha.toISOString(),
      creadas: detalle.length,
      detalle,
    };
  }
}
