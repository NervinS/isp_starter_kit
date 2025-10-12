// src/controllers/materiales.disponibles.controller.ts
import { Controller, Get, Query } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Controller('materiales') // el prefijo /v1 lo pone el globalPrefix
export class MaterialesDisponiblesController {
  constructor(private readonly ds: DataSource) {}

  @Get('disponibles')
  async disponibles(@Query('almacen') almacen?: string) {
    try {
      // Si existe la tabla materiales, devolvemos id/codigo/nombre/precio
      const exists = await this.ds.query(
        `SELECT to_regclass('public.materiales') AS exists`,
      );
      if (exists?.[0]?.exists) {
        // precio: si no existe columna, forzamos '0.00'
        // intentamos leer columna precio; si falla, caemos al SELECT simple
        try {
          const rows = await this.ds.query(
            `
            SELECT id, codigo, nombre,
                   COALESCE(TO_CHAR(precio::numeric, 'FM999999990.00'), '0.00') AS precio
              FROM materiales
             ORDER BY id
             LIMIT 50
            `,
          );
          return { ok: true, total: rows.length, items: rows };
        } catch {
          const rows = await this.ds.query(
            `
            SELECT id, codigo, nombre, '0.00' AS precio
              FROM materiales
             ORDER BY id
             LIMIT 50
            `,
          );
          return { ok: true, total: rows.length, items: rows };
        }
      }

      // Fallback si no hay tabla
      return { ok: true, total: 0, items: [] };
    } catch {
      return { ok: true, total: 0, items: [] };
    }
  }
}
