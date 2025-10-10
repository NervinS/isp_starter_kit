// src/controllers/materiales.disponibles.controller.ts
import { BadRequestException, Controller, Get, Query, Res } from '@nestjs/common';
import { ApiOperation, ApiQuery, ApiResponse, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';

@ApiTags('Materiales')
@Controller('materiales') // el /v1 lo agrega el globalPrefix en main.ts
export class MaterialesDisponiblesController {
  @Get('disponibles')
  @ApiOperation({
    summary: 'Alias a inventario/stock por almacén (solo lectura)',
    description:
      'Retorna los materiales disponibles en un almacén. Internamente redirige (307) a /v1/inventario/stock/almacen/:codigo.',
  })
  @ApiQuery({ name: 'almacen', required: true, example: 'CENTRAL' })
  @ApiResponse({ status: 307, description: 'Redirect to /v1/inventario/stock/almacen/:codigo' })
  @ApiResponse({ status: 400, description: 'Parámetros inválidos' })
  async disponibles(@Query('almacen') almacen: string, @Res() res: Response) {
    const codigo = String(almacen ?? '').trim();
    if (!codigo) throw new BadRequestException('almacen requerido');
    // Redirección temporal para conservar método y cuerpo (si tuviera):
    res.redirect(307, `/v1/inventario/stock/almacen/${encodeURIComponent(codigo)}`);
  }
}
