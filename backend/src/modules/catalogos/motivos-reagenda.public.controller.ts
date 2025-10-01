// src/modules/catalogos/motivos-reagenda.public.controller.ts
import { Controller, Get } from '@nestjs/common';
import { DataSource } from 'typeorm';

/**
 * Estructura de salida normalizada para catálogos públicos.
 * Mantenemos "id" como string para ser homogéneos con otros endpoints.
 */
type CatalogItem = {
  id: string;
  nombre: string;
  activo: boolean;
};

/**
 * Controlador público con ruta en kebab-case:
 * GET /v1/catalogos/motivos-reagenda
 *
 * Nota: La tabla public.catalogo_motivos_reagenda tiene columnas:
 *   - id (serial/int)
 *   - nombre (text, UNIQUE)
 *   - activo (boolean)
 * No tiene columna "orden". Ordenamos por nombre ascendente.
 */
@Controller('catalogos')
export class MotivosReagendaPublicControllerKebab {
  constructor(private readonly ds: DataSource) {}

  @Get('motivos-reagenda')
  async listarKebab(): Promise<{ items: CatalogItem[] }> {
    const rows = await this.ds.query(
      `
      SELECT
        id::text AS id,
        nombre,
        activo
      FROM public.catalogo_motivos_reagenda
      WHERE activo = true
      ORDER BY nombre ASC
      `
    );
    return { items: rows };
  }
}

/**
 * Controlador público con ruta en underscore:
 * GET /v1/catalogos/motivos_reagenda/items
 *
 * Se mantiene la misma semántica que el kebab-case y el mismo shape { items: [...] }.
 */
@Controller('catalogos/motivos_reagenda')
export class MotivosReagendaPublicControllerUnderscore {
  constructor(private readonly ds: DataSource) {}

  @Get('items')
  async listarUnderscore(): Promise<{ items: CatalogItem[] }> {
    const rows = await this.ds.query(
      `
      SELECT
        id::text AS id,
        nombre,
        activo
      FROM public.catalogo_motivos_reagenda
      WHERE activo = true
      ORDER BY nombre ASC
      `
    );
    return { items: rows };
  }
}
