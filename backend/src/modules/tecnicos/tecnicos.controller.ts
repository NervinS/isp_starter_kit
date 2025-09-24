// src/modules/tecnicos/tecnicos.controller.ts
import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { TecnicosService } from './tecnicos.service';

type CerrarDto = {
  tecnicoId: string;
  materiales?: Array<{ materialIdInt: number; cantidad: number }>;
};

@ApiTags('tecnicos')
@Controller('tecnicos')
export class TecnicosController {
  constructor(private readonly svc: TecnicosService) {}

  @Get(':tecnicoId/ordenes/pendientes')
  @ApiOperation({ summary: 'Órdenes pendientes (agendada/en_progreso) para un técnico' })
  pendientes(@Param('tecnicoId') tecnicoId: string) {
    return this.svc.pendientes(tecnicoId);
  }

  @Post(':tecnicoId/ordenes/:ordenId/iniciar')
  @ApiOperation({ summary: 'Inicia una orden por ID (UUID) — idempotente' })
  iniciarPorId(
    @Param('tecnicoId') tecnicoId: string,
    @Param('ordenId') ordenId: string,
  ) {
    return this.svc.iniciarOrdenPorId(tecnicoId, ordenId);
  }

  @Post(':tecnicoId/ordenes/codigo/:codigo/iniciar')
  @ApiOperation({ summary: 'Inicia una orden por código — idempotente' })
  iniciarPorCodigo(
    @Param('tecnicoId') tecnicoId: string,
    @Param('codigo') codigo: string,
  ) {
    return this.svc.iniciarOrdenPorCodigo(tecnicoId, codigo);
  }

  @Post(':tecnicoId/ordenes/:ordenId/cerrar')
  @ApiOperation({
    summary:
      'Cierra una orden por ID (UUID), aplica materiales y firma — idempotente',
  })
  cerrarPorId(
    @Param('tecnicoId') tecnicoId: string,
    @Param('ordenId') ordenId: string,
    @Body() body: CerrarDto,
  ) {
    return this.svc.cerrarOrdenPorId(tecnicoId, ordenId, body);
  }

  @Post(':tecnicoId/ordenes/codigo/:codigo/cerrar')
  @ApiOperation({
    summary:
      'Cierra una orden por código, aplica materiales y firma — idempotente',
  })
  cerrarPorCodigo(
    @Param('tecnicoId') tecnicoId: string,
    @Param('codigo') codigo: string,
    @Body() body: CerrarDto,
  ) {
    // 🔧 Fix: antes llamaba a cerrarOrdenPorCodigo (no existe). El método correcto es cerrarPorCodigo.
    return this.svc.cerrarPorCodigo(tecnicoId, codigo, body);
  }
}
