// src/modules/tecnicos/tecnico.ordenes.controller.ts
import { Controller, Get, NotFoundException, Param } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { TecnicosService } from './tecnicos.service';

@ApiTags('tecnico')
@Controller('tecnico/ordenes')
export class TecnicoOrdenesController {
  constructor(private readonly svc: TecnicosService) {}

  @Get(':codigo')
  @ApiOperation({ summary: 'Detalle unificado de orden por código (para front técnico)' })
  async detalle(@Param('codigo') codigo: string) {
    const r = await this.svc.getOrdenDetalleByCodigo(codigo);
    if (!r) throw new NotFoundException('Orden no encontrada');
    return r;
  }
}
