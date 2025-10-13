// src/modules/ordenes/ordenes.transversal.controller.ts
import { Controller, Get, Param, Post, Body } from '@nestjs/common';
import { OrdenesTransversalService } from './ordenes.transversal.service';

@Controller('ordenes') // 👈 SIN 'v1' porque ya existe setGlobalPrefix('v1')
export class OrdenesTransversalController {
  constructor(private readonly svc: OrdenesTransversalService) {}

  @Get(':codigo')
  async byCodigo(@Param('codigo') codigo: string) {
    return this.svc.getOrdenTransversal(codigo);
  }

  @Post(':codigo/evidencias')
  async evidencias(
    @Param('codigo') codigo: string,
    @Body() body: { items?: Array<{ url: string; tipo?: string }> } = {},
  ) {
    return this.svc.subirEvidencias(codigo, body.items ?? []);
  }

  @Post(':codigo/cerrar')
  async cerrar(@Param('codigo') codigo: string, @Body() body: any = {}) {
    return this.svc.cerrarOrden(codigo, body ?? {});
  }

  @Post(':codigo/equipos')
  async equipos(
    @Param('codigo') codigo: string,
    @Body() body: unknown, // { acciones:[...] } o array directo o {}
  ) {
    return this.svc.aplicarAccionesEquipos(codigo, body as any);
  }
}
