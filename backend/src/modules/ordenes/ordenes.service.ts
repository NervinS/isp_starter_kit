// src/modules/ordenes/ordenes.service.ts
import { Injectable, HttpException, HttpStatus } from '@nestjs/common';
import { DataSource } from 'typeorm';

type EquipoIn = {
  equipo_tipo: 'ONT' | 'REPEATER';
  serial: string;
  accion: 'asignar' | 'retirar' | 'mantener';
};

type CierreIn = {
  tecnicoId?: string | null;      // compat (uuid si aplica), no se usa para almacén
  tecnicoIdNum?: number | null;   // ID numérico del técnico (requerido si vienen equipos)
  materiales?: Array<{ materialId: number; cantidad: number }>;
  equipos?: EquipoIn[];
  payload_cierre?: Record<string, any> | null;
  firmaBase64?: string | null;
  evidenciasBase64?: string[];
  notas?: string | null;
};

@Injectable()
export class OrdenesService {
  constructor(private readonly ds: DataSource) {}

  /**
   * Cierre administrativo/idempotente por CÓDIGO.
   * - Idempotencia de cierre: si ya estaba cerrada => _idempotent=true.
   * - Idempotencia por ACCIÓN de equipo (asignar/retirar/mantener):
   *     ON CONFLICT (orden_id, equipo_tipo, serial, accion) DO NOTHING
   *     y sólo ejecuta movimiento si INSERTó.
   * - Movimientos usando firma explícita: fn_mov_simple(text, uuid, int, numeric, text).
   */
  async cerrarCompletoAdmin(codigo: string, body: CierreIn) {
    return this.ds.transaction('READ COMMITTED', async (em) => {
      // 1) Lock de orden
      const [orden] = await em.query(
        `SELECT * FROM public.ordenes WHERE codigo=$1 FOR UPDATE`,
        [codigo],
      );
      if (!orden) {
        throw new HttpException('Orden no existe', HttpStatus.NOT_FOUND);
      }

      // 2) Idempotencia de cierre
      if (orden.cerrada_at) {
        return {
          ok: true,
          codigo: orden.codigo,
          estado: orden.estado,
          cerradaAt: orden.cerrada_at,
          pdfUrl: orden.pdf_url ?? null,
          _idempotent: true,
        };
      }

      // 3) Persistir payload de cierre si vino
      if (body?.payload_cierre) {
        await em.query(
          `UPDATE public.ordenes SET payload_cierre=$2, updated_at=now() WHERE id=$1`,
          [orden.id, body.payload_cierre],
        );
      }

      // 4) Equipos (si vienen)
      const equipos: EquipoIn[] = Array.isArray(body?.equipos) ? body!.equipos : [];

      if (equipos.length > 0) {
        // 4.1 Resolver almacén técnico a partir de tecnicoIdNum
        if (!(typeof body?.tecnicoIdNum === 'number' && Number.isFinite(body.tecnicoIdNum))) {
          throw new HttpException(
            'tecnicoIdNum es requerido cuando se envían equipos',
            HttpStatus.BAD_REQUEST,
          );
        }
        const tecnicoIdNum = body.tecnicoIdNum!;
        const [alm] = await em.query(
          `SELECT id FROM public.almacenes WHERE tecnico_id=$1 LIMIT 1`,
          [tecnicoIdNum],
        );
        if (!alm?.id) {
          throw new HttpException(
            `No existe almacén para tecnico_id=${tecnicoIdNum}`,
            HttpStatus.CONFLICT,
          );
        }
        const almacenId: string = alm.id;

        // 4.2 Mapeo equipo -> material
        const catalogRows = await em.query(
          `SELECT equipo_tipo, material_id
             FROM public.catalogo_equipos_material
            WHERE equipo_tipo IN ('ONT','REPEATER')`,
        );
        const cat: Record<string, number> = {};
        for (const r of catalogRows) cat[r.equipo_tipo] = Number(r.material_id);

        for (const e of equipos) {
          if (!cat[e.equipo_tipo]) {
            throw new HttpException(
              `Sin mapeo de material para equipo_tipo=${e.equipo_tipo}`,
              HttpStatus.CONFLICT,
            );
          }
        }

        // 4.3 Procesar por ACCIÓN con idempotencia
        for (const e of equipos) {
          // INSERT idempotente por (orden_id, equipo_tipo, serial, accion)
          // Si es "mantener": no hay movimiento; marcamos aplicado=true siempre.
          if (e.accion === 'mantener') {
            await em.query(
              `
              INSERT INTO public.orden_equipos (orden_id, equipo_tipo, serial, accion, aplicado)
              VALUES ($1,$2,$3,$4,true)
              ON CONFLICT (orden_id, equipo_tipo, serial, accion)
              DO UPDATE SET aplicado=true
              `,
              [orden.id, e.equipo_tipo, e.serial, e.accion],
            );
            continue;
          }

          // Para asignar/retirar: sólo mover si INSERTó
          const inserted = await em.query(
            `
            INSERT INTO public.orden_equipos (orden_id, equipo_tipo, serial, accion, aplicado)
            VALUES ($1,$2,$3,$4,false)
            ON CONFLICT (orden_id, equipo_tipo, serial, accion) DO NOTHING
            RETURNING id
            `,
            [orden.id, e.equipo_tipo, e.serial, e.accion],
          );

          if (inserted.length) {
            const materialId = cat[e.equipo_tipo];
            const nota = `[orden ${orden.codigo}] ${e.accion} ${e.equipo_tipo} ${e.serial}`;

            // Tipo de movimiento
            const tipoMov = e.accion === 'asignar' ? 'egreso' : 'ingreso';

            // Llama a la firma explícita: (text, uuid, int, numeric, text)
            await em.query(
              `SELECT public.fn_mov_simple($1::text, $2::uuid, $3::int, $4::numeric, $5::text)`,
              [tipoMov, almacenId, materialId, 1, nota],
            );

            // Marca aplicado
            await em.query(
              `UPDATE public.orden_equipos SET aplicado=true WHERE id=$1`,
              [inserted[0].id],
            );
          }
          // Si no insertó, ya existía => idempotente por acción => no mueve.
        }
      }

      // 5) Marcar orden cerrada
      await em.query(
        `UPDATE public.ordenes
            SET estado='cerrada',
                cerrada_at = now()
          WHERE id=$1`,
        [orden.id],
      );

      // 6) Efectos en usuario según tipo (mantengo la misma lógica que tenías)
      if (orden.usuario_id) {
        if (['INS', 'REC', 'COR', 'BAJ'].includes(orden.tipo)) {
          await em.query(
            `UPDATE public.usuarios u
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
          // Placeholder por si manejas estado físico aparte:
          // await em.query(`UPDATE public.usuarios SET estado_conexion='conectado', updated_at=now() WHERE id=$1`, [orden.usuario_id]);
        }
      }

      // 7) (Opcional) Generar PDF según tu servicio (no-op aquí)

      // 8) Respuesta
      const [after] = await em.query(
        `SELECT codigo, estado, cerrada_at, pdf_url FROM public.ordenes WHERE id=$1`,
        [orden.id],
      );

      return {
        ok: true,
        codigo: after.codigo,
        estado: after.estado,
        cerradaAt: after.cerrada_at,
        pdfUrl: after.pdf_url ?? null,
        _idempotent: false,
      };
    });
  }

  /**
   * Guardado incremental (autosave) para payload_abierto/evidencias.
   * No cambia estado. Devuelve updatedAt.
   */
  async guardarParcial(
    codigo: string,
    patch: Partial<{ payload_abierto: any; evidencias: any }>,
  ) {
    return this.ds.transaction('READ COMMITTED', async (em) => {
      const [orden] = await em.query(
        `SELECT id, payload_abierto, evidencias FROM public.ordenes WHERE codigo=$1 FOR UPDATE`,
        [codigo],
      );
      if (!orden) throw new HttpException('Orden no existe', HttpStatus.NOT_FOUND);

      const mergedAbierto = patch.payload_abierto
        ? { ...(orden.payload_abierto ?? {}), ...patch.payload_abierto }
        : orden.payload_abierto ?? null;

      const mergedEvid = patch.evidencias
        ? { ...(orden.evidencias ?? {}), ...patch.evidencias }
        : orden.evidencias ?? null;

      await em.query(
        `UPDATE public.ordenes
            SET payload_abierto=$2,
                evidencias=$3,
                updated_at=now()
          WHERE id=$1`,
        [orden.id, mergedAbierto, mergedEvid],
      );

      const [after] = await em.query(
        `SELECT updated_at FROM public.ordenes WHERE id=$1`,
        [orden.id],
      );

      return {
        ok: true,
        codigo,
        payload_abierto: mergedAbierto,
        evidencias: mergedEvid,
        updatedAt: after.updated_at,
      };
    });
  }
}
