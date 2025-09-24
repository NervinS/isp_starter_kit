// src/modules/catalogos/motivos-reagenda.public.controller.ts
import { Controller, Get, Query } from '@nestjs/common';
import { CatalogosService } from './catalogos.service';

@Controller('catalogos')
export class MotivosReagendaPublicControllerKebab {
  constructor(private readonly catalogos: CatalogosService) {}

  // GET /v1/catalogos/motivos-reagenda
  @Get('motivos-reagenda')
  async listarKebab(@Query('soloActivos') soloActivos?: string) {
    const onlyActive = String(soloActivos ?? '').toLowerCase() === 'true';
    const items = await this.catalogos.motivosReagendaListarPublico(onlyActive);
    return {
      ok: true,
      items: items.map(({ id, codigo, nombre }) => ({ id, codigo, nombre })),
    };
  }
}

@Controller('catalogos/motivos_reagenda')
export class MotivosReagendaPublicControllerUnderscore {
  constructor(private readonly catalogos: CatalogosService) {}

  // GET /v1/catalogos/motivos_reagenda/items
  @Get('items')
  async listarUnderscore(@Query('soloActivos') soloActivos?: string) {
    const onlyActive = String(soloActivos ?? '').toLowerCase() === 'true';
    const items = await this.catalogos.motivosReagendaListarPublico(onlyActive);
    return {
      ok: true,
      items: items.map(({ id, codigo, nombre }) => ({ id, codigo, nombre })),
    };
  }
}
