// src/modules/jobs/jobs.service.ts
import { Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';

type TipoSim = 'COR' | 'REC';

@Injectable()
export class JobsService {
  constructor(private readonly ds: DataSource) {}

  async simular(tipo: TipoSim, fechaISO?: string) {
    const fecha = fechaISO ? new Date(fechaISO) : new Date();

    // 1) Asegurar secuencia (idempotente)
    await this.ds.query(`
      CREATE SEQUENCE IF NOT EXISTS public.ordenes_codigo_seq;
    `);

    // 2) Tomamos algunos usuarios como muestra
    const usuarios: Array<{ id: number }> = await this.ds.query(
      `SELECT id FROM usuarios ORDER BY id LIMIT 5`,
    );

    const detalle: Array<{ codigo: string; tipo: TipoSim; usuarioId: number }> = [];

    for (const u of usuarios) {
      const r = await this.ds.transaction('READ COMMITTED', async (em) => {
        // Generar el código **en SQL** usando la secuencia, evitando condiciones de carrera
        const [ins] = await em.query(
          `
          INSERT INTO ordenes (
            codigo, estado, tecnico_id,  tipo, subtotal, total, usuario_id, created_at, updated_at
          )
          VALUES (
            ($1 || '-' || to_char(nextval('public.ordenes_codigo_seq'), 'FM000000')),
            'agendada',
            NULL,
            $1,
            0,
            0,
            $2,
            NOW(),
            NOW()
          )
          RETURNING id, codigo
          `,
          [tipo, u.id],
        );

        // Cerrar inmediatamente la orden creada
        await em.query(
          `
          UPDATE ordenes
             SET cerrada_at = NOW(),
                 estado     = 'cerrada',
                 updated_at = NOW()
           WHERE id = $1
             AND cerrada_at IS NULL
          `,
          [ins.id],
        );

        // Ajustar estado del usuario según el tipo simulado
        const nuevoEstado =
          tipo === 'COR' ? 'desconectado'
          : tipo === 'REC' ? 'instalado'
          : null;

        if (nuevoEstado) {
          await em.query(
            `UPDATE usuarios SET estado = $2, updated_at = NOW() WHERE id = $1`,
            [u.id, nuevoEstado],
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
