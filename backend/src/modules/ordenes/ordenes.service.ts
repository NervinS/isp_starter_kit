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

  // ============================================================
  // Helpers
  // ============================================================
  private async getOrdenByCodigo(codigo: string) {
    const rows = await this.ds.query(
      `SELECT id, codigo, tipo, estado, cerrada_at, usuario_id
         FROM public.ordenes
        WHERE codigo=$1
        LIMIT 1`,
      [codigo],
    );
    return rows[0] ?? null;
  }

  private async getOrdenIdByCodigoOrFail(codigo: string) {
    const o = await this.getOrdenByCodigo(codigo);
    if (!o) {
      throw new HttpException('Orden no existe', HttpStatus.NOT_FOUND);
    }
    return o;
  }

  // ============================================================
  // Evidencias ricas
  // ============================================================
  async addEvidenciasRich(
    codigo: string,
    input: {
      items: Array<{ kind: string; key: string; meta?: any }>;
      mergeJson?: Record<string, any> | null;
      firmaKey?: string | null;
    },
  ) {
    const orden = await this.getOrdenIdByCodigoOrFail(codigo);

    let inserted = 0;
    if (Array.isArray(input.items) && input.items.length > 0) {
      for (const it of input.items) {
        const kind = String(it?.kind ?? '').trim();
        const key = String(it?.key ?? '').trim();
        if (!kind || !key) continue;

        // idempotente por (orden_id, kind, key)
        await this.ds.query(
          `
          INSERT INTO public.orden_evidencias (orden_id, kind, key, meta)
          VALUES ($1,$2,$3, COALESCE($4,'{}'::jsonb))
          ON CONFLICT (orden_id, kind, key) DO NOTHING
          `,
          [orden.id, kind, key, it?.meta ?? {}],
        );
        // contamos con RETURNING? para saber si insertó
        const r = await this.ds.query(
          `SELECT 1 FROM public.orden_evidencias WHERE orden_id=$1 AND kind=$2 AND key=$3`,
          [orden.id, kind, key],
        );
        if (r?.length) inserted++; // aproximado (doble consulta) pero simple
      }
    }

    // Merge legacy JSON evidencias + firmaKey en ordenes (compatibilidad)
    if (input.mergeJson || input.firmaKey !== undefined) {
      const row = await this.ds.query(
        `SELECT evidencias, firma_key FROM public.ordenes WHERE id=$1`,
        [orden.id],
      );
      const curEvid = row?.[0]?.evidencias ?? null;
      const merged =
        input.mergeJson && typeof input.mergeJson === 'object'
          ? { ...(curEvid ?? {}), ...input.mergeJson }
          : curEvid;

      await this.ds.query(
        `
        UPDATE public.ordenes
           SET evidencias = $2,
               firma_key  = COALESCE($3, firma_key),
               updated_at = now()
         WHERE id=$1
        `,
        [orden.id, merged, input.firmaKey ?? null],
      );
    }

    return { ok: true, codigo, items: inserted };
  }

  // ============================================================
  // Cierre + snapshot (orden_cierres)
  // ============================================================
  async cerrarConSnapshot(
    codigo: string,
    input: { payload_cierre?: any; pdfKey?: string | null; idemKey?: string | null },
  ) {
    return this.ds.transaction('READ COMMITTED', async (em) => {
      // 1) Lock orden
      const [orden] = await em.query(
        `SELECT id, codigo, tipo, estado, cerrada_at, usuario_id
           FROM public.ordenes
          WHERE codigo=$1
          FOR UPDATE`,
        [codigo],
      );
      if (!orden) {
        throw new HttpException('Orden no existe', HttpStatus.NOT_FOUND);
      }
      if (orden.estado === 'anulada') {
        throw new HttpException('no se puede cerrar en estado=anulada', HttpStatus.BAD_REQUEST);
      }

      // 2) Si ya hay snapshot => idempotente
      const snapRows = await em.query(
        `SELECT id, orden_id, tipo, payload_json, evidencias_json, pdf_key, created_at
           FROM public.orden_cierres
          WHERE orden_id=$1
          LIMIT 1`,
        [orden.id],
      );
      if (snapRows.length) {
        return {
          ok: true,
          _idempotent: true,
          codigo: orden.codigo,
          estado: 'cerrada',
          cerradaAt: orden.cerrada_at ?? new Date().toISOString(),
          cierre: {
            tipo: snapRows[0].tipo,
            pdfKey: snapRows[0].pdf_key ?? null,
            createdAt: snapRows[0].created_at,
          },
        };
      }

      // 3) Recolectar evidencias ricas
      const evidRows = await em.query(
        `SELECT kind, key, meta, created_at
           FROM public.orden_evidencias
          WHERE orden_id=$1
          ORDER BY created_at ASC`,
        [orden.id],
      );
      const evidencias_json = evidRows.map((r: any) => ({
        kind: r.kind,
        key: r.key,
        meta: r.meta ?? {},
        created_at: r.created_at,
      }));

      // 4) Payload de cierre (si no vino, objeto vacío)
      const payload_json = input?.payload_cierre ?? {};

      // 5) Insert snapshot
      await em.query(
        `
        INSERT INTO public.orden_cierres
          (orden_id, tipo, payload_json, evidencias_json, pdf_key)
        VALUES ($1,       $2,   $3,            $4,              $5)
        ON CONFLICT (orden_id) DO NOTHING
        `,
        [orden.id, orden.tipo, payload_json, evidencias_json, input?.pdfKey ?? null],
      );

      // 6) Marcar orden cerrada (si no lo estaba)
      if (!orden.cerrada_at || orden.estado !== 'cerrada') {
        await em.query(
          `UPDATE public.ordenes
              SET estado='cerrada',
                  cerrada_at=COALESCE(cerrada_at, now()),
                  payload_cierre=COALESCE(payload_cierre, $2),
                  updated_at=now()
            WHERE id=$1`,
          [orden.id, payload_json],
        );
      }

      // 7) Efectos en usuario (misma lógica que tenías)
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
      }

      // 8) Leer snapshot recién creado
      const [snap] = await em.query(
        `SELECT tipo, pdf_key, created_at
           FROM public.orden_cierres
          WHERE orden_id=$1`,
        [orden.id],
      );

      return {
        ok: true,
        _idempotent: false,
        codigo: orden.codigo,
        estado: 'cerrada',
        cerradaAt: new Date().toISOString(),
        cierre: {
          tipo: snap?.tipo ?? orden.tipo,
          pdfKey: snap?.pdf_key ?? null,
          createdAt: snap?.created_at ?? null,
        },
      };
    });
  }

  async getCierre(codigo: string) {
    const orden = await this.getOrdenByCodigo(codigo);
    if (!orden) return null;

    const rows = await this.ds.query(
      `SELECT tipo, payload_json, evidencias_json, pdf_key, version, cerrado_por, created_at
         FROM public.orden_cierres
        WHERE orden_id=$1
        LIMIT 1`,
      [orden.id],
    );
    if (!rows.length) return null;

    const c = rows[0];
    return {
      ok: true,
      codigo: orden.codigo,
      tipo: c.tipo,
      payload: c.payload_json ?? {},
      evidencias: Array.isArray(c.evidencias_json) ? c.evidencias_json : [],
      pdfKey: c.pdf_key ?? null,
      version: c.version ?? 1,
      cerradoPor: c.cerrado_por ?? null,
      createdAt: c.created_at,
    };
  }

  // ============================================================
  // (Se mantiene tu cierre administrativo previo por compatibilidad)
  // ============================================================
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

      // 4) Equipos (si vienen) — lógica existente
      const equipos: EquipoIn[] = Array.isArray(body?.equipos) ? body!.equipos : [];

      if (equipos.length > 0) {
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

        for (const e of equipos) {
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
            const tipoMov = e.accion === 'asignar' ? 'egreso' : 'ingreso';

            await em.query(
              `SELECT public.fn_mov_simple($1::text, $2::uuid, $3::int, $4::numeric, $5::text)`,
              [tipoMov, almacenId, materialId, 1, nota],
            );

            await em.query(
              `UPDATE public.orden_equipos SET aplicado=true WHERE id=$1`,
              [inserted[0].id],
            );
          }
        }
      }

      await em.query(
        `UPDATE public.ordenes
            SET estado='cerrada',
                cerrada_at = now()
          WHERE id=$1`,
        [orden.id],
      );

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
      }

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

  // Guardado incremental (autosave) para payload_abierto/evidencias.
  async guardarParcial(
    codigo: string,
    patch: Partial<{ payload_abierto: any; evidencias: any }>,
  ) {
    return this.ds.transaction('READ COMMITTED', async (em) => {
      const [orden] = await em.query(
        `SELECT id, payload_abierto, evidencias FROM public.ordenes WHERE codigo=$1 FOR UPDATE`,
        [codigo],
      );
      if (!orden)
        throw new HttpException('Orden no existe', HttpStatus.NOT_FOUND);

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
