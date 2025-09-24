// src/modules/agenda/agenda.service.ts
import { Injectable, Logger, BadRequestException, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';

type Turno = 'am' | 'pm';

type AsignarParams = {
  tecnicoId: string;
  fecha: string; // YYYY-MM-DD
  turno: Turno;
};

type ReagendarParams = {
  fecha: string; // YYYY-MM-DD
  turno: Turno;
};

type AnularParams = {
  motivo: string;
  motivoCodigo?: string;
};

@Injectable()
export class AgendaService {
  private readonly logger = new Logger(AgendaService.name);
  constructor(private readonly dataSource: DataSource) {}

  private one<T = any>(rows: T[], notFoundMsg = 'Orden no encontrada'): T {
    if (!rows || rows.length === 0) {
      throw new NotFoundException(notFoundMsg);
    }
    return rows[0];
  }

  async listar(q?: { q?: string; desde?: string; hasta?: string }) {
    const params: any[] = [];
    const where: string[] = [];

    if (q?.q) {
      params.push(`%${q.q.trim()}%`);
      where.push(`o.codigo ILIKE $${params.length}`);
    }
    if (q?.desde) {
      params.push(q.desde);
      where.push(`o.agendado_para >= $${params.length}::date`);
    }
    if (q?.hasta) {
      params.push(q.hasta);
      where.push(`o.agendado_para <= $${params.length}::date`);
    }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    const items = await this.dataSource.query(
      `
      SELECT
        o.codigo,
        o.estado,
        to_char(o.agendado_para,'YYYY-MM-DD') AS "agendadoPara",
        o.turno,
        o.agendada_at AS "agendadaAt",
        o.tecnico_id AS "tecnicoId"
      FROM ordenes o
      ${whereSql}
      ORDER BY o.agendado_para NULLS LAST, o.codigo ASC
      LIMIT 200
      `,
      params,
    );

    return { ok: true, items };
  }

  async asignarPorCodigo(codigo: string, dto: AsignarParams) {
    const { tecnicoId, fecha, turno } = dto;

    if (!tecnicoId) throw new BadRequestException('tecnicoId es obligatorio');
    if (!fecha) throw new BadRequestException('fecha es obligatoria (YYYY-MM-DD)');
    if (!turno) throw new BadRequestException('turno es obligatorio (am|pm)');

    const res = await this.dataSource.query(
      `
      UPDATE ordenes
      SET
        tecnico_id    = $2,
        agendado_para = $3::date,
        turno         = $4::text,
        agendada_at   = now(),
        estado        = 'agendada'
      WHERE codigo = $1
      RETURNING
        codigo,
        estado,
        to_char(agendado_para,'YYYY-MM-DD') AS "agendadoPara",
        turno,
        agendada_at AS "agendadaAt",
        tecnico_id  AS "tecnicoId"
      `,
      [codigo, tecnicoId, fecha, turno],
    );

    const orden = this.one(res);
    const payload = { ok: true, orden };
    this.logger.log(`[ASIGNAR] ${codigo} -> ${JSON.stringify(payload)}`);
    return payload;
  }

  async reagendarPorCodigo(codigo: string, dto: ReagendarParams) {
    const { fecha, turno } = dto;

    if (!fecha) throw new BadRequestException('fecha es obligatoria (YYYY-MM-DD)');
    if (!turno) throw new BadRequestException('turno es obligatorio (am|pm)');

    const res = await this.dataSource.query(
      `
      UPDATE ordenes
      SET
        agendado_para = $2::date,
        turno         = $3::text,
        agendada_at   = now(),
        estado        = 'agendada'
      WHERE codigo = $1
      RETURNING
        codigo,
        estado,
        to_char(agendado_para,'YYYY-MM-DD') AS "agendadoPara",
        turno,
        agendada_at AS "agendadaAt",
        tecnico_id  AS "tecnicoId"
      `,
      [codigo, fecha, turno],
    );

    const orden = this.one(res);
    const payload = { ok: true, orden };
    this.logger.log(`[REAGENDAR] ${codigo} -> ${JSON.stringify(payload)}`);
    return payload;
  }

  /** Cancelar agenda (mantiene estado actual, solo limpia fecha/turno/marca de agenda) */
  async cancelarPorCodigo(codigo: string) {
    const res = await this.dataSource.query(
      `
      UPDATE ordenes
      SET
        agendado_para = NULL,
        turno         = NULL,
        agendada_at   = NULL
        -- NOTA: estado se mantiene; se usa 'anular' para pasar a cancelada
      WHERE codigo = $1
      RETURNING
        codigo,
        estado,
        to_char(agendado_para,'YYYY-MM-DD') AS "agendadoPara",
        turno,
        agendada_at AS "agendadaAt",
        tecnico_id  AS "tecnicoId"
      `,
      [codigo],
    );

    const orden = this.one(res);
    const payload = { ok: true, orden };
    this.logger.log(`[CANCELAR] ${codigo} -> ${JSON.stringify(payload)}`);
    return payload;
  }

  /** Anular orden: estado=cancelada, guarda motivo/s, libera agenda y técnico */
  async anularPorCodigo(codigo: string, dto: AnularParams) {
    const { motivo, motivoCodigo } = dto;
    if (!motivo || !motivo.trim()) {
      throw new BadRequestException('motivo es obligatorio');
    }

    const res = await this.dataSource.query(
      `
      UPDATE ordenes
      SET
        estado              = 'cancelada',
        motivo_cancelacion  = $2,
        motivo_codigo       = $3,
        cancelada_at        = now(),
        -- liberar agenda
        agendado_para       = NULL,
        turno               = NULL,
        agendada_at         = NULL,
        -- liberar técnico
        tecnico_id          = NULL
      WHERE codigo = $1
      RETURNING
        codigo,
        estado,
        motivo_cancelacion AS "motivo",
        motivo_codigo      AS "motivoCodigo",
        cancelada_at       AS "canceladaAt",
        to_char(agendado_para,'YYYY-MM-DD') AS "agendadoPara",
        turno,
        agendada_at        AS "agendadaAt",
        tecnico_id         AS "tecnicoId"
      `,
      [codigo, motivo.trim(), motivoCodigo ?? null],
    );

    const orden = this.one(res);
    const payload = { ok: true, orden };
    this.logger.log(`[ANULAR] ${codigo} -> ${JSON.stringify(payload)}`);
    return payload;
  }
}
