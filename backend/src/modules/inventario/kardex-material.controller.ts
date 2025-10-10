// src/modules/inventario/kardex-material.controller.ts
import { Controller, Get, Query, BadRequestException, Res } from '@nestjs/common';
import { Response } from 'express';
import { ApiOperation, ApiQuery, ApiResponse, ApiTags } from '@nestjs/swagger';

@ApiTags('Inventario')
@Controller('inventario/kardex')
export class KardexMaterialController {
  @Get('material')
  @ApiOperation({ summary: 'Alias 307 → /v1/inventario/kardex con filtros por material' })
  @ApiQuery({ name: 'materialId', required: true, description: 'ID numérico del material' })
  @ApiQuery({ name: 'from', required: false, description: 'ISO date desde (incl.)' })
  @ApiQuery({ name: 'to', required: false, description: 'ISO date hasta (incl.)' })
  @ApiQuery({ name: 'almacen', required: false, description: 'Código de almacén (ej: CENTRAL, ALM-PRINC, TEC-6)' })
  @ApiQuery({ name: 'tecnicoId', required: false, description: 'Filtrar por técnico (numérico)' })
  @ApiQuery({ name: 'limit', required: false, description: 'Límite de filas (1..500). Default 50' })
  @ApiResponse({ status: 307, description: 'Redirect temporal al kardex canónico' })
  async alias(
    @Query('materialId') materialId?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('almacen') almacen?: string,
    @Query('tecnicoId') tecnicoId?: string,
    @Query('limit') limit?: string,
    @Res() res?: Response,
  ) {
    if (!materialId || isNaN(+materialId)) {
      throw new BadRequestException('materialId requerido (numérico)');
    }
    // Construimos la querystring preservando sólo los params presentes
    const params = new URLSearchParams();
    params.set('materialId', String(+materialId));
    if (from) params.set('from', from);
    if (to) params.set('to', to);
    if (almacen) params.set('almacen', almacen);
    if (tecnicoId && !isNaN(+tecnicoId)) params.set('tecnicoId', String(+tecnicoId));
    if (limit && !isNaN(+limit)) params.set('limit', String(+limit));

    const location = `/v1/inventario/kardex?${params.toString()}`;
    return res!.redirect(307, location);
  }
}
