// src/modules/agenda/agenda.service.ts
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { DataSource } from 'typeorm';

function asUuidOrNull(v: any): string | null {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  // UUID v4 simple check
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    s,
  )
    ? s
    : null;
}

@Injectable()
export class AgendaService {
  constructor(private readonly ds: DataSource) {}

  /**
   * Asignar por código
   * Corrige COALESCE uuid vs integer casteando tecnicoId con NULLIF/CAST.
   */
  async asignarPorCodigo(
    codigo: string,
    fecha: string,
    turno: 'am' | 'pm',
    tecnicoId?: string,
  ) {
    if (!codigo) throw new BadRequestException('codigo requerido');
    if (!fecha) throw new BadRequestException('fecha requerida');

    const tecUuid = asUuidOrNull(tecnicoId ?? '') ?? null;

    const res = await this.ds.query(
      `
      UPDATE ordenes o
      SET
        estado = 'agendada',
        agendado_para = $2::date,
        turno = $3,
        agendada_at = NOW(),
        tecnico_id = CAST(NULLIF($4,'') AS uuid)
      WHERE o.codigo = $1
      RETURNING
        codigo,
        estado,
        agendado_para AS "agendadoPara",
        turno,
        agendada_at AS "agendadaAt",
        tecnico_id AS "tecnicoId"
    `,
      [codigo, fecha, turno, tecUuid ?? ''],
    );

    if (!res?.length) throw new NotFoundException('Orden no encontrada');
    return { ok: true, orden: [res, res.length] };
  }

  /**
   * Reagendar por código
   */
  async reagendarPorCodigo(
    codigo: string,
    fecha: string,
    turno: 'am' | 'pm',
    motivoCodigo?: string,
    motivo?: string,
  ) {
    if (!codigo) throw new BadRequestException('codigo requerido');
    if (!fecha) throw new BadRequestException('fecha requerida');

    const res = await this.ds.query(
      `
      UPDATE ordenes o
      SET
        estado = 'agendada',
        agendado_para = $2::date,
        turno = $3,
        agendada_at = NOW(),
        tecnico_id = NULL,
        motivo = COALESCE($5, 'Reagendada'),
        motivo_codigo = $4
      WHERE o.codigo = $1
      RETURNING
        codigo,
        estado,
        agendado_para AS "agendadoPara",
        turno,
        agendada_at AS "agendadaAt",
        tecnico_id AS "tecnicoId",
        motivo,
        motivo_codigo AS "motivoCodigo"
    `,
      [codigo, fecha, turno, motivoCodigo ?? null, motivo ?? null],
    );

    if (!res?.length) throw new NotFoundException('Orden no encontrada');
    return { ok: true, orden: [res, res.length] };
  }

  /**
   * Cancelar por código (deja sin fecha/turno y sin técnico)
   */
  async cancelarPorCodigo(codigo: string) {
    if (!codigo) throw new BadRequestException('codigo requerido');

    const res = await this.ds.query(
      `
      UPDATE ordenes o
      SET
        estado = 'agendada',
        agendado_para = NULL,
        turno = NULL,
        agendada_at = NULL,
        tecnico_id = NULL
      WHERE o.codigo = $1
      RETURNING
        codigo,
        estado,
        agendado_para AS "agendadoPara",
        turno,
        agendada_at AS "agendadaAt",
        tecnico_id AS "tecnicoId"
    `,
      [codigo],
    );

    if (!res?.length) throw new NotFoundException('Orden no encontrada');
    return { ok: true, orden: [res, res.length] };
  }

  /**
   * Anular por código: evita usar columna inexistente "motivo_cancelacion".
   * Usa "estado = 'anulada'" y almacena el motivo en "motivo".
   */
  async anularPorCodigo(codigo: string, motivo?: string) {
    if (!codigo) throw new BadRequestException('codigo requerido');

    const textoMotivo =
      typeof motivo === 'string' && motivo.trim().length >= 3
        ? motivo.trim()
        : 'Anulada';

    const res = await this.ds.query(
      `
      UPDATE ordenes o
      SET
        estado = 'anulada',
        motivo = $2
      WHERE o.codigo = $1
      RETURNING
        codigo,
        estado,
        motivo
    `,
      [codigo, textoMotivo],
    );

    if (!res?.length) throw new NotFoundException('Orden no encontrada');
    return { ok: true, orden: [res, res.length] };
  }
}
