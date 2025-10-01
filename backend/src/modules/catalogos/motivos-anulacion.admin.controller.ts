// src/modules/catalogos/motivos-anulacion.admin.controller.ts
import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
} from '@nestjs/common';
import { DataSource } from 'typeorm';

/**
 * Endpoints administrativos (CRUD simple).
 * Ruta base: /v1/admin/catalogos/motivos_anulacion/items
 *
 * Nota: Si luego activas guards/JWT, colócalos aquí.
 */
@Controller('admin/catalogos/motivos_anulacion/items')
export class MotivosAnulacionAdminController {
  constructor(private readonly ds: DataSource) {}

  @Get()
  async listAll() {
    return this.ds.query(
      `SELECT id, nombre, activo
         FROM public.catalogo_motivos_anulacion
        ORDER BY nombre ASC`,
    );
  }

  @Post()
  async create(@Body() body: any) {
    const nombre = body?.nombre?.trim();
    const activo = body?.activo ?? true;
    if (!nombre) throw new BadRequestException('nombre requerido');

    const rows = await this.ds.query(
      `INSERT INTO public.catalogo_motivos_anulacion (nombre, activo)
       VALUES ($1, $2)
       ON CONFLICT (nombre) DO UPDATE
           SET activo = EXCLUDED.activo
       RETURNING id, nombre, activo`,
      [nombre, !!activo],
    );
    return rows[0];
  }

  @Patch(':id')
  async update(@Param('id') id: string, @Body() body: any) {
    const nombre = body?.nombre?.trim();
    const activo = body?.activo;

    if (nombre == null && activo == null) {
      throw new BadRequestException('nada para actualizar');
    }

    const rows = await this.ds.query(
      `UPDATE public.catalogo_motivos_anulacion
          SET nombre = COALESCE($2, nombre),
              activo = COALESCE($3, activo)
        WHERE id = $1
        RETURNING id, nombre, activo`,
      [id, nombre ?? null, activo ?? null],
    );
    if (!rows.length) throw new BadRequestException('id no existe');
    return rows[0];
  }

  @Delete(':id')
  async remove(@Param('id') id: string) {
    const rows = await this.ds.query(
      `DELETE FROM public.catalogo_motivos_anulacion
        WHERE id = $1
        RETURNING id`,
      [id],
    );
    if (!rows.length) throw new BadRequestException('id no existe');
    return { ok: true, id: rows[0].id };
  }
}
