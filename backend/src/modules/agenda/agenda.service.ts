// src/modules/agenda/agenda.service.ts
import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { DataSource } from 'typeorm';

/** DTO interno mínimo para anular; evita depender de otros archivos */
type AnularParams = {
  motivo: string;
  motivoCodigo?: string | null;
};

@Injectable()
export class AgendaService {
  private readonly logger = new Logger(AgendaService.name);

  constructor(private readonly dataSource: DataSource) {}

  /** Util: normaliza el resultado de DataSource.query a un array de una orden */
  private one(res: any[]): any[] {
    if (Array.isArray(res) && res.length > 0) {
      return res.map((r) => r);
    }
    return [];
  }

  /** Asignar agenda (fecha/turno/técnico) y dejar estado=agendada */
  async asignarPorCodigo(
    codigo: string,
    fecha: string,
    turno: 'am' | 'pm',
    tecnicoId?: string | null,
  ) {
    const res = await this.dataSource.query(
      `
      UPDATE ordenes
      SET
        agendado_para = $2::date,
        turno         = $3::text,
        agendada_at   = now(),
        estado        = 'agendada',
        tecnico_id    = COALESCE($4::uuid, tecnico_id)
      WHERE codigo = $1
      RETURNING
        codigo,
        estado,
        to_char(agendado_para,'YYYY-MM-DD') AS "agendadoPara",
        turno,
        agendada_at AS "agendadaAt",
        tecnico_id  AS "tecnicoId"
      `,
      [codigo, fecha, turno, (tecnicoId ?? null)],
    );

    const orden = this.one(res);
    const payload = { ok: true, orden };
    this.logger.log(`[ASIGNAR] ${codigo} -> ${JSON.stringify(payload)}`);
    return payload;
  }

  /**
   * Reagendar agenda (fecha/turno) y persistir motivo de REAGENDA.
   * Regla: si vienen ambos, se guardan ambos; si no vienen, se ponen en NULL.
   */
  async reagendarPorCodigo(
    codigo: string,
    fecha: string,
    turno: 'am' | 'pm',
    motivo?: string | null,
    motivoCodigo?: string | null,
  ) {
    const motivoTxt   = (motivo ?? '').trim() || null;
    const motivoCod   = (motivoCodigo ?? '').trim() || null;

    const res = await this.dataSource.query(
      `
      UPDATE ordenes
      SET
        agendado_para           = $2::date,
        turno                   = $3::text,
        agendada_at             = now(),
        estado                  = 'agendada',
        -- Persistencia directa (sin COALESCE): lo que venga, se guarda
        motivo_reagenda         = $4::text,
        motivo_reagenda_codigo  = $5::text
      WHERE codigo = $1
      RETURNING
        codigo,
        estado,
        to_char(agendado_para,'YYYY-MM-DD') AS "agendadoPara",
        turno,
        agendada_at AS "agendadaAt",
        tecnico_id  AS "tecnicoId",
        motivo_reagenda        AS "motivo",
        motivo_reagenda_codigo AS "motivoCodigo"
      `,
      [codigo, fecha, turno, motivoTxt, motivoCod],
    );

    const orden = this.one(res);
    const payload = { ok: true, orden };
    this.logger.log(`[REAGENDAR] ${codigo} -> ${JSON.stringify(payload)}`);
    return payload;
  }

  /** Cancelar agenda (limpia fecha/turno/marca de agenda; no cambia estado) */
  async cancelarPorCodigo(codigo: string) {
    const res = await this.dataSource.query(
      `
      UPDATE ordenes
      SET
        agendado_para = NULL,
        turno         = NULL,
        agendada_at   = NULL
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
      [codigo, motivo.trim(), (motivoCodigo ?? null)],
    );

    const orden = this.one(res);
    const payload = { ok: true, orden };
    this.logger.log(`[ANULAR] ${codigo} -> ${JSON.stringify(payload)}`);
    return payload;
  }
}
