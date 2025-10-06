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
import { OrdenesService } from './ordenes.service';

type CerrarOrdenBody = {
  materiales?: Array<{ materialId: number; cantidad: number }>;
  notas?: string | null;
  equipos?: Array<{
    equipo_tipo: 'ONT' | 'REPEATER';
    serial: string;
    accion: 'asignar' | 'retirar' | 'mantener';
  }>;
  payload_cierre?: Record<string, any> | null;
  firmaBase64?: string | null;
  evidenciasBase64?: string[];
  // para mapear almacén técnico por numero (p.ej. TEC-6 => 6)
  tecnicoIdNum?: number | null;
  // compat si envías UUID de técnico por otro flujo
  tecnicoId?: string | null;
};

type GuardarBody = {
  payload_abierto?: Record<string, any> | null;
  evidencias?: Record<string, any> | null;
};

@Controller('ordenes') // => /v1/ordenes
export class OrdenesController {
  constructor(
    private readonly ds: DataSource,
    private readonly ordenesService: OrdenesService,
  ) {}

  /**
   * GET /v1/ordenes
   * Filtros:
   *  - tipo: 'INS' | ...
   *  - estado: 'creada' | 'agendada' | 'en_proceso' | 'cerrada' | ...
   *  - tecnicoId: UUID
   *  - desde, hasta: YYYY-MM-DD (agendado_para)
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

    const limit = Math.min(Math.max(Number(limitStr ?? 50) || 50, 1), 200);
    const offset = Math.max(Number(offsetStr ?? 0) || 0, 0);
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
   * PUT /v1/ordenes/:codigo/guardar
   * Guardado incremental de payload_abierto/evidencias (autosave).
   */
  @Put(':codigo/guardar')
  async guardar(@Param('codigo') codigo: string, @Body() body: GuardarBody) {
    return this.ordenesService.guardarParcial(codigo, {
      payload_abierto: body?.payload_abierto ?? null,
      evidencias: body?.evidencias ?? null,
    });
  }

  /**
   * PUT /v1/ordenes/:codigo/cerrar
   * Cierre administrativo con soporte de equipos/materiales.
   */
  @Put(':codigo/cerrar')
  async cerrar(@Param('codigo') codigo: string, @Body() body: CerrarOrdenBody) {
    const cierre = {
      tecnicoId: body?.tecnicoId ?? null,
      tecnicoIdNum: body?.tecnicoIdNum ?? null,
      materiales: body?.materiales ?? [],
      equipos: Array.isArray(body?.equipos) ? body!.equipos : [],
      payload_cierre: body?.payload_cierre ?? null,
      firmaBase64: body?.firmaBase64 ?? null,
      evidenciasBase64: Array.isArray(body?.evidenciasBase64)
        ? body!.evidenciasBase64
        : [],
      notas: body?.notas ?? null,
    };
    return this.ordenesService.cerrarCompletoAdmin(codigo, cierre);
  }
}
