// src/modules/ordenes/ordenes.controller.ts
import {
  BadRequestException,
  Controller,
  Get,
  Put,
  Param,
  Body,
  Query,
} from '@nestjs/common';
import { DataSource } from 'typeorm';

type CerrarOrdenBody = {
  materiales?: Array<{ materialId: number; cantidad: number }>;
  notas?: string | null;
};

@Controller('ordenes') // se servirá como /v1/ordenes por el GlobalPrefix
export class OrdenesController {
  constructor(private readonly ds: DataSource) {}

  /**
   * GET /v1/ordenes
   * Filtros:
   *  - tipo: 'INS' | ...
   *  - estado: 'pendiente' | 'agendada' | 'en_proceso' | 'cerrada' | ...
   *  - tecnicoId: UUID
   *  - desde, hasta: YYYY-MM-DD (filtra por agendado_para)
   *  - limit, offset: paginación (1..200)
   */
  @Get()
  async listar(
    @Query('tipo') tipo?: string,
    @Query('estado') estado?: string,
    @Query('tecnicoId') tecnicoId?: string,
    @Query('desde') desde?: string,
    @Query('hasta') hasta?: string,
    @Query('limit') limitStr?: string,
    @Query('offset') offsetStr?: string,
  ) {
    const where: string[] = [];
    const params: any[] = [];

    if (tipo) {
      where.push(`o.tipo = $${params.length + 1}`);
      params.push(tipo);
    }
    if (estado) {
      where.push(`o.estado = $${params.length + 1}`);
      params.push(estado);
    }
    if (tecnicoId) {
      where.push(`o.tecnico_id = $${params.length + 1}`);
      params.push(tecnicoId);
    }
    if (desde) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(desde)) {
        throw new BadRequestException('desde inválido (YYYY-MM-DD)');
      }
      where.push(`o.agendado_para >= $${params.length + 1}`);
      params.push(desde);
    }
    if (hasta) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(hasta)) {
        throw new BadRequestException('hasta inválido (YYYY-MM-DD)');
      }
      where.push(`o.agendado_para <= $${params.length + 1}`);
      params.push(hasta);
    }

    const limit = (() => {
      const n = Number(limitStr ?? 50);
      if (!Number.isFinite(n)) return 50;
      return Math.min(Math.max(n, 1), 200);
    })();

    const offset = (() => {
      const n = Number(offsetStr ?? 0);
      if (!Number.isFinite(n) || n < 0) return 0;
      return n;
    })();

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    const sql = `
      SELECT
        o.id,
        o.codigo,
        o.tipo,
        o.estado,
        o.agendado_para          AS "agendadoPara",
        o.turno,
        o.agendada_at            AS "agendadaAt",
        o.iniciada_at            AS "iniciadaAt",
        o.cerrada_at             AS "cerradaAt",
        o.tecnico_id             AS "tecnicoId",
        v.codigo                 AS "ventaCodigo",
        v.cliente_nombre         AS "clienteNombre",
        v.cliente_apellido       AS "clienteApellido",
        v.documento              AS "documento",
        v.plan                   AS "plan",
        v.mensual_total          AS "mensual",
        v.total                  AS "total"
      FROM public.ordenes o
      LEFT JOIN public.ventas v ON v.id = o.venta_id
      ${whereSql}
      ORDER BY
        o.agendado_para ASC NULLS LAST,
        o.codigo ASC
      LIMIT ${limit} OFFSET ${offset}
    `;
    const items = await this.ds.query(sql, params);

    const [{ total }] = await this.ds.query(
      `SELECT COUNT(*)::int AS total FROM public.ordenes o ${whereSql}`,
      params,
    );

    return { total, limit, offset, items };
  }

  /**
   * PUT /v1/ordenes/:codigo/cerrar
   * (Se deja compatible; si tu versión tenía lógica de cierre/inventario,
   * conserva esa implementación y añade sólo el método listar de arriba.)
   */
  @Put(':codigo/cerrar')
  async cerrar(
    @Param('codigo') codigo: string,
    @Body() body: CerrarOrdenBody,
  ) {
    // No-op mínima para compat; reemplaza por tu implementación real si ya la tenías.
    return {
      codigo,
      estado: 'cerrada',
      materiales: body?.materiales ?? [],
      notas: body?.notas ?? null,
    };
  }
}
