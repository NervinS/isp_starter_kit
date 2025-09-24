// src/modules/agenda/agenda.controller.ts
import { Body, Controller, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiParam, ApiResponse, ApiTags } from '@nestjs/swagger';
import { AgendaService } from './agenda.service';
import { AsignarOrdenDto } from './dto/asignar-orden.dto';
import { ReagendarOrdenDto } from './dto/reagendar-orden.dto';
import { AnularOrdenDto } from './dto/anular-orden.dto';

@ApiTags('Agenda')
@Controller('agenda')
export class AgendaController {
  constructor(private readonly agendaService: AgendaService) {}

  @Get('ordenes')
  @ApiOperation({ summary: 'Listar órdenes (vista agenda)' })
  async listar(@Query() q: any) {
    return this.agendaService.listar(q);
  }

  @Post('ordenes/:codigo/asignar')
  @HttpCode(200)
  @ApiOperation({ summary: 'Asignar técnico/fecha/turno a una orden' })
  @ApiParam({ name: 'codigo', example: 'ORD-DEMO-2001' })
  @ApiResponse({ status: 200 })
  async asignar(@Param('codigo') codigo: string, @Body() body: AsignarOrdenDto) {
    return await this.agendaService.asignarPorCodigo(codigo, body);
  }

  @Post('ordenes/:codigo/reagendar')
  @HttpCode(200)
  @ApiOperation({ summary: 'Reagendar fecha/turno de una orden' })
  @ApiParam({ name: 'codigo', example: 'ORD-DEMO-2001' })
  @ApiResponse({ status: 200 })
  async reagendar(@Param('codigo') codigo: string, @Body() body: ReagendarOrdenDto) {
    return await this.agendaService.reagendarPorCodigo(codigo, body);
  }

  @Post('ordenes/:codigo/cancelar')
  @HttpCode(200)
  @ApiOperation({ summary: 'Cancelar agenda (quitar fecha/turno) de una orden' })
  @ApiParam({ name: 'codigo', example: 'ORD-DEMO-2001' })
  @ApiResponse({ status: 200 })
  async cancelar(@Param('codigo') codigo: string) {
    return await this.agendaService.cancelarPorCodigo(codigo);
  }

  @Post('ordenes/:codigo/anular')
  @HttpCode(200)
  @ApiOperation({ summary: 'Anular la orden: estado=cancelada, registra motivo y libera agenda+técnico' })
  @ApiParam({ name: 'codigo', example: 'ORD-DEMO-2001' })
  @ApiResponse({ status: 200 })
  async anular(@Param('codigo') codigo: string, @Body() body: AnularOrdenDto) {
    return await this.agendaService.anularPorCodigo(codigo, body);
  }
}
