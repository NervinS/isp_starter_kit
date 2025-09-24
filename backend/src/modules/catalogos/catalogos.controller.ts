// src/modules/catalogos/catalogos.controller.ts
// src/modules/catalogos/catalogos.controller.ts
import { Controller, Get, Query } from '@nestjs/common';
import { CatalogosService } from './catalogos.service';

@Controller('catalogos')
export class CatalogosController {
  constructor(private readonly catalogos: CatalogosService) {}

  /**
   * Municipios
   * Ej: GET /v1/catalogos/municipios?q=bo&activos=true
   */
  @Get('municipios')
  async municipios(
    @Query('q') q: string = '',
    @Query('activos') activosRaw?: string,
  ) {
    const activos =
      typeof activosRaw === 'string'
        ? ['true', '1', 't'].includes(activosRaw.toLowerCase())
        : undefined;

    // Cast a any para ser tolerantes a la firma del service (objeto o params sueltos)
    const items = await (this.catalogos as any).listarMunicipios?.(
      { q, activos },
    ) ?? (await (this.catalogos as any).listarMunicipios?.(q, activos));

    return { ok: true, items: items ?? [] };
  }

  /**
   * Vías
   * Ej: GET /v1/catalogos/vias?q=av&activos=true
   */
  @Get('vias')
  async vias(
    @Query('q') q: string = '',
    @Query('activos') activosRaw?: string,
  ) {
    const activos =
      typeof activosRaw === 'string'
        ? ['true', '1', 't'].includes(activosRaw.toLowerCase())
        : undefined;

    const items = await (this.catalogos as any).listarVias?.({ q, activos }) ??
      (await (this.catalogos as any).listarVias?.(q, activos));

    return { ok: true, items: items ?? [] };
  }

  /**
   * Sectores
   * Ej: GET /v1/catalogos/sectores?municipio=XXX&zona=NORTE&q=z1&activos=true&format=simple
   */
  @Get('sectores')
  async sectores(
    @Query('municipio') municipio?: string,
    @Query('zona') zona?: string,
    @Query('q') q: string = '',
    @Query('activos') activosRaw?: string,
    @Query('format') format?: string,
  ) {
    const activos =
      typeof activosRaw === 'string'
        ? ['true', '1', 't'].includes(activosRaw.toLowerCase())
        : undefined;

    const items =
      (await (this.catalogos as any).listarSectores?.({
        municipio,
        zona,
        q,
        activos,
        format,
      })) ??
      (await (this.catalogos as any).listarSectores?.(
        municipio,
        zona,
        q,
        activos,
        format,
      ));

    return { ok: true, items: items ?? [] };
  }
}

