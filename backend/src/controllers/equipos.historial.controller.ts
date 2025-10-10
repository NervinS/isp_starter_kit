// src/controllers/equipos.historial.controller.ts
import { Controller, Get, Query, BadRequestException, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { ApiOperation, ApiQuery, ApiResponse, ApiTags } from '@nestjs/swagger';

@ApiTags('Equipos')
@Controller('equipos') // /v1 lo pone el globalPrefix
export class EquiposHistorialController {
  constructor(private readonly dataSource: DataSource) {}

  @Get('historial')
  @ApiOperation({
    summary: 'Consultar equipo por SN o MAC (read-only)',
    description:
      'Devuelve el equipo actual por sn o mac. El arreglo "historial" queda vacío por ahora (sin tabla de movimientos).',
  })
  @ApiQuery({ name: 'sn', required: false })
  @ApiQuery({ name: 'mac', required: false })
  @ApiResponse({ status: 200, description: 'OK' })
  @ApiResponse({ status: 400, description: 'Parámetros inválidos' })
  @ApiResponse({ status: 404, description: 'No encontrado' })
  async historial(@Query('sn') _sn?: string, @Query('mac') _mac?: string) {
    const sn = (_sn ?? '').trim();
    const mac = (_mac ?? '').trim();

    if (!sn && !mac) {
      throw new BadRequestException('Debe proporcionar sn o mac');
    }

    // Búsqueda case-insensitive sobre SN o MAC (si se pasan ambos, cualquiera que matche)
    const rows = await this.dataSource.query(
      `
      select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, created_at, updated_at
      from equipos
      where ($1::text is not null and $1 <> '' and upper(sn)  = upper($1))
         or ($2::text is not null and $2 <> '' and upper(mac) = upper($2))
      limit 1
      `,
      [sn || null, mac || null],
    );

    if (!rows || rows.length === 0) {
      throw new NotFoundException('Equipo no encontrado');
    }

    const equipo = rows[0];

    return {
      equipo,
      historial: [], // reservado para cuando exista bitácora
    };
  }
}
