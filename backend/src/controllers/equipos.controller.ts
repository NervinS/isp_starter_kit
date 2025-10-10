// src/controllers/equipos.controller.ts
import { Controller, Get, Query, BadRequestException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { ApiOperation, ApiQuery, ApiResponse, ApiTags } from '@nestjs/swagger';

@ApiTags('Equipos')
@Controller('equipos') // el /v1 lo agrega el globalPrefix en main.ts
export class EquiposController {
  constructor(private readonly dataSource: DataSource) {}

  @Get('disponibles')
  @ApiOperation({ summary: 'Listar equipos disponibles por tipo' })
  @ApiQuery({ name: 'tipo', enum: ['ONU', 'REPETIDOR', 'ONT'], required: true })
  @ApiQuery({ name: 'tecnico', required: false, description: 'Reservado; hoy se ignora' })
  @ApiResponse({ status: 200, description: 'OK' })
  @ApiResponse({ status: 400, description: 'Parámetros inválidos' })
  async disponibles(@Query('tipo') tipo?: string) {
    if (!tipo) throw new BadRequestException('tipo requerido');
    const norm = tipo.toUpperCase() === 'ONT' ? 'ONU' : tipo.toUpperCase();
    if (!['ONU', 'REPETIDOR'].includes(norm)) {
      throw new BadRequestException('tipo debe ser ONU|REPETIDOR|ONT');
    }
    const rows = await this.dataSource.query(
      `
      select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id
      from equipos
      where estado = 'EN_STOCK'
        and owner_tipo = 'ALMACEN'
        and tipo = $1
      order by created_at desc
      `,
      [norm],
    );
    return rows;
  }
}
