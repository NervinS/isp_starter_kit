// src/modules/agenda/agenda.controller.ts
import {
  BadRequestException,
  Body,
  Controller,
  Param,
  Post,
} from '@nestjs/common';
import { DataSource } from 'typeorm';

type AsignarBody = {
  fecha: string;             // YYYY-MM-DD
  turno?: string | null;     // 'AM' | 'PM' | ...
  tecnicoId?: string | null; // UUID opcional
};

type ReagendarBody = {
  fecha: string;             // YYYY-MM-DD
  turno?: string | null;
  tecnicoId?: string | null;
  motivo?: string | null;    // se puede validar contra catalogo_motivos_reagenda si viene
};

type CancelarBody = {
  motivo: string;            // texto libre (por ahora)
};

type AnularBody = {
  motivoId?: string | number | null; // preferido (FK catálogo)
  motivo?: string | null;            // fallback libre si no hay catálogo
};

@Controller('agenda') // /v1/agenda por GlobalPrefix
export class AgendaController {
  constructor(private readonly ds: DataSource) {}

  private assertFecha(fecha?: string) {
    if (!fecha || !/^\d{4}-\d{2}-\d{2}$/.test(fecha)) {
      throw new BadRequestException('fecha inválida (YYYY-MM-DD)');
    }
  }

  private async findOrdenForUpdate(trx: any, codigo: string) {
    const rows = await trx.query(
      `SELECT * FROM public.ordenes WHERE codigo=$1 FOR UPDATE`,
      [codigo],
    );
    if (!rows.length) throw new BadRequestException('orden no existe');
    return rows[0];
  }

  private async validarMotivoEnCatalogo(
    trx: any,
    tabla: 'catalogo_motivos_reagenda' | 'catalogo_motivos_anulacion',
    motivo?: string | null,
    obligatorio = false,
  ) {
    const m = motivo?.trim();
    if (obligatorio && !m) {
      throw new BadRequestException('motivo requerido');
    }
    if (!m) return; // no hay nada que validar

    const hit = await trx.query(
      `SELECT 1 FROM ${tabla} WHERE activo = true AND nombre = $1 LIMIT 1`,
      [m],
    );
    if (!hit.length) {
      const etiqueta =
        tabla === 'catalogo_motivos_reagenda'
          ? 'catálogo de motivos de reagenda'
          : 'catálogo de motivos de anulación';
      throw new BadRequestException(`motivo no válido (${etiqueta})`);
    }
  }

  @Post('ordenes/:codigo/asignar')
  async asignar(@Param('codigo') codigo: string, @Body() body: AsignarBody) {
    const { fecha, turno = null, tecnicoId = null } = body ?? {};
    this.assertFecha(fecha);

    return this.ds.transaction(async (trx) => {
      const ord = await this.findOrdenForUpdate(trx, codigo);
      if (!['INS', 'MAN', 'SUP', 'REP', 'ACT', 'BAJ'].includes(ord.tipo)) {
        throw new BadRequestException('tipo de orden no soportado');
      }
      if (!['pendiente', 'agendada', 'en_proceso'].includes(ord.estado)) {
        throw new BadRequestException(`no se puede asignar en estado=${ord.estado}`);
      }

      await trx.query(
        `UPDATE public.ordenes
           SET agendado_para=$2,
               turno=$3,
               tecnico_id=$4,
               estado='agendada',
               agendada_at=now()
         WHERE id=$1`,
        [ord.id, fecha, turno, tecnicoId],
      );

      const out = await trx.query(
        `SELECT id, codigo, tipo, estado,
                agendado_para AS "agendadoPara",
                turno,
                tecnico_id   AS "tecnicoId",
                agendada_at  AS "agendadaAt"
           FROM public.ordenes WHERE id=$1`,
        [ord.id],
      );
      return out[0];
    });
  }

  @Post('ordenes/:codigo/reagendar')
  async reagendar(@Param('codigo') codigo: string, @Body() body: ReagendarBody) {
    const { fecha, turno = null, tecnicoId = null, motivo = null } = body ?? {};
    this.assertFecha(fecha);

    return this.ds.transaction(async (trx) => {
      const ord = await this.findOrdenForUpdate(trx, codigo);
      if (!['pendiente', 'agendada', 'en_proceso'].includes(ord.estado)) {
        throw new BadRequestException(`no se puede reagendar en estado=${ord.estado}`);
      }

      // Validar motivo si viene (por nombre en catálogo), pero no es obligatorio
      await this.validarMotivoEnCatalogo(trx, 'catalogo_motivos_reagenda', motivo, false);

      await trx.query(
        `UPDATE public.ordenes
           SET agendado_para = $2,
               turno         = $3,
               tecnico_id    = $4,
               estado        = 'agendada',
               agendada_at   = now()
         WHERE id = $1`,
        [ord.id, fecha, turno, tecnicoId],
      );

      const out = await trx.query(
        `SELECT id, codigo, tipo, estado,
                agendado_para AS "agendadoPara",
                turno,
                tecnico_id   AS "tecnicoId",
                agendada_at  AS "agendadaAt"
           FROM public.ordenes WHERE id=$1`,
        [ord.id],
      );
      return out[0];
    });
  }

  @Post('ordenes/:codigo/cancelar')
  async cancelar(@Param('codigo') codigo: string, @Body() body: CancelarBody) {
    const motivo = body?.motivo?.trim();
    if (!motivo) throw new BadRequestException('motivo requerido');

    return this.ds.transaction(async (trx) => {
      const ord = await this.findOrdenForUpdate(trx, codigo);
      if (['cerrada', 'anulada', 'cancelada'].includes(ord.estado)) {
        const out = await trx.query(
          `SELECT id, codigo, tipo, estado, cancelada_at AS "canceladaAt",
                  motivo_cancelacion AS "motivoCancelacion"
             FROM public.ordenes WHERE id=$1`,
          [ord.id],
        );
        return out[0];
      }

      await trx.query(
        `UPDATE public.ordenes
           SET estado='cancelada',
               cancelada_at=now(),
               motivo_cancelacion=$2
         WHERE id=$1`,
        [ord.id, motivo],
      );

      const out = await trx.query(
        `SELECT id, codigo, tipo, estado, cancelada_at AS "canceladaAt",
                motivo_cancelacion AS "motivoCancelacion"
           FROM public.ordenes WHERE id=$1`,
        [ord.id],
      );
      return out[0];
    });
  }

  @Post('ordenes/:codigo/anular')
  async anular(@Param('codigo') codigo: string, @Body() body: AnularBody) {
    const motivoIdRaw = body?.motivoId ?? null;            // preferido (FK)
    const motivoLibre = (body?.motivo ?? '').trim() || null; // fallback

    return this.ds.transaction(async (trx) => {
      const ord = await this.findOrdenForUpdate(trx, codigo);

      // Normalizar motivoId a number si viene string
      const motivoId =
        motivoIdRaw != null && motivoIdRaw !== ''
          ? Number(motivoIdRaw)
          : null;

      // Validar motivoId contra catálogo si vino
      let motivoAnulacionId: number | null = null;
      if (motivoId != null && !Number.isNaN(motivoId)) {
        const cat = await trx.query(
          `SELECT id
             FROM public.catalogo_motivos_anulacion
            WHERE id=$1::int AND activo=true`,
          [motivoId],
        );
        if (!cat.length) {
          throw new BadRequestException('motivoId inválido o inactivo');
        }
        motivoAnulacionId = Number(cat[0].id);
      }

      // Si ya está anulada, permitir completar motivos faltantes (idempotencia flexible)
      if (ord.estado === 'anulada') {
        const debeActualizar =
          (motivoAnulacionId != null && (ord.motivo_anulacion_id == null)) ||
          (motivoLibre && (!ord.motivo_cancelacion || String(ord.motivo_cancelacion).trim() === ''));

        if (debeActualizar) {
          await trx.query(
            `UPDATE public.ordenes
               SET motivo_cancelacion   = COALESCE($2, motivo_cancelacion),
                   motivo_anulacion_id  = COALESCE($3, motivo_anulacion_id)
             WHERE id = $1`,
            [ord.id, motivoLibre, motivoAnulacionId],
          );
        }

        const out2 = await trx.query(
          `SELECT o.id, o.codigo, o.tipo, o.estado,
                  o.motivo_anulacion_id AS "motivoAnulacionId",
                  o.motivo_cancelacion  AS "motivoCancelacion"
             FROM public.ordenes o
            WHERE o.id = $1`,
          [ord.id],
        );
        return out2[0];
      }

      // Si no está anulada, exigir algún motivo (id de catálogo o texto)
      if (motivoAnulacionId == null && !motivoLibre) {
        throw new BadRequestException('motivoId o motivo requerido');
      }

      await trx.query(
        `UPDATE public.ordenes
            SET estado='anulada',
                cancelada_at        = COALESCE(cancelada_at, now()),
                motivo_cancelacion  = COALESCE($2, motivo_cancelacion),
                motivo_anulacion_id = COALESCE($3, motivo_anulacion_id)
          WHERE id=$1`,
        [ord.id, motivoLibre, motivoAnulacionId],
      );

      const out = await trx.query(
        `SELECT o.id, o.codigo, o.tipo, o.estado,
                o.motivo_anulacion_id AS "motivoAnulacionId",
                o.motivo_cancelacion  AS "motivoCancelacion"
           FROM public.ordenes o
          WHERE o.id = $1`,
        [ord.id],
      );
      return out[0];
    });
  }
}
