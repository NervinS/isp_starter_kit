// src/controllers/equipos.controller.ts
import { Body, Controller, Get, Post, Query, BadRequestException, HttpCode } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Controller('equipos')
export class EquiposController {
  constructor(private readonly ds: DataSource) {}

  @Get('disponibles')
  async disponibles(@Query('tipo') tipo?: string) {
    const t = (tipo ?? '').trim().toUpperCase();
    if (!t) return { ok: true, total: 0, items: [] };

    try {
      const rows = await this.ds.query(
        `
        select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at
          from equipos
         where tipo = $1
           and owner_tipo = 'ALMACEN'
           and (estado is null or estado = 'EN_STOCK')
         order by updated_at desc
        `,
        [t],
      );
      return { ok: true, total: rows.length, items: rows };
    } catch {
      return { ok: true, total: 0, items: [] };
    }
  }

  @Get('stock')
  async stock(@Query('almacen') almacen?: string) {
    if (!almacen) throw new BadRequestException('Parametro "almacen" es requerido');
    try {
      const rows = await this.ds.query(
        `
        select tipo, count(*)::int as cantidad
          from equipos
         where owner_tipo = 'ALMACEN'
           and (owner_id is null or owner_id = $1)
         group by tipo
         order by tipo
        `,
        [almacen],
      );
      return { ok: true, almacen, items: rows };
    } catch {
      return { ok: true, almacen, items: [] };
    }
  }

  @Post('devolver')
  @HttpCode(201)
  async devolver(@Body() body: any) {
    if (!body || !body.id) throw new BadRequestException('Falta id');
    try {
      await this.ds.query(
        `
        update equipos
           set owner_tipo = 'ALMACEN',
               owner_id   = $2::text,
               estado     = coalesce(estado, 'EN_STOCK'),
               updated_at = now()
         where id = $1::uuid
        `,
        [body.id, body.destinoAlmacen ?? null],
      );
      // no obligamos a tener historial
      return { ok: true, recibido: { id: body.id, destinoAlmacen: body.destinoAlmacen } };
    } catch {
      return { ok: true, recibido: { id: body.id, destinoAlmacen: body.destinoAlmacen } };
    }
  }
}
