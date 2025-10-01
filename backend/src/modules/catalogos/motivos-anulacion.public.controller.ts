// src/modules/catalogos/motivos-anulacion.public.controller.ts
import { Controller, Get } from '@nestjs/common';
import { DataSource } from 'typeorm';

/**
 * Endpoints públicos para el front.
 * Ruta efectiva: /v1/catalogos/motivos-anulacion
 */
@Controller('catalogos/motivos-anulacion')
export class MotivosAnulacionPublicControllerKebab {
  constructor(private readonly ds: DataSource) {}

  @Get()
  async list() {
    const rows = await this.ds.query(
      `SELECT id, nombre, activo
         FROM public.catalogo_motivos_anulacion
        WHERE activo = true
        ORDER BY nombre ASC`,
    );
    return { items: rows };
  }
}
