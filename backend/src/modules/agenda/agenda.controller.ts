// src/modules/agenda/agenda.controller.ts
import {
  BadRequestException,
  Body,
  Controller,
  HttpCode,
  Param,
  Post,
} from '@nestjs/common';
import {
  ApiBody,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiTags,
} from '@nestjs/swagger';
import { AgendaService } from './agenda.service';
import { AsignarOrdenDto } from './dto/asignar-orden.dto';
import { ReagendarOrdenDto } from './dto/reagendar-orden.dto';
import { AnularOrdenDto } from './dto/anular-orden.dto';

// helper: literal 'am' | 'pm'
function ensureTurno(value: unknown): 'am' | 'pm' {
  if (value === 'am' || value === 'pm') return value;
  throw new BadRequestException('turno debe ser "am" o "pm"');
}

@ApiTags('Agenda')
@Controller('agenda')
export class AgendaController {
  constructor(private readonly agendaService: AgendaService) {}

  @Post('ordenes/:codigo/asignar')
  @HttpCode(200)
  @ApiOperation({ summary: 'Asignar técnico/fecha/turno a una orden' })
  @ApiParam({ name: 'codigo', example: 'ORD-DEMO-2001' })
  @ApiResponse({ status: 200 })
  @ApiBody({ type: AsignarOrdenDto })
  async asignar(@Param('codigo') codigo: string, @Body() body: AsignarOrdenDto) {
    const turno = ensureTurno(body.turno);
    return await this.agendaService.asignarPorCodigo(
      codigo,
      body.fecha,
      turno,
      body.tecnicoId ?? null,
    );
  }

  @Post('ordenes/:codigo/reagendar')
  @HttpCode(200)
  @ApiOperation({
    summary: 'Reagendar fecha/turno (opcional: motivo y motivoCodigo)',
  })
  @ApiParam({ name: 'codigo', example: 'ORD-DEMO-2001' })
  @ApiResponse({ status: 200 })
  @ApiBody({ type: ReagendarOrdenDto })
  async reagendar(
    @Param('codigo') codigo: string,
    @Body() body: ReagendarOrdenDto,
  ) {
    const turno = ensureTurno(body.turno);
    // ⚠️ Orden CORRECTO de args: ... fecha, turno, motivo, motivoCodigo
    return await this.agendaService.reagendarPorCodigo(
      codigo,
      body.fecha,
      turno,
      body.motivo ?? null,
      body.motivoCodigo ?? null,
    );
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
  @ApiOperation({
    summary:
      'Anular la orden: estado=cancelada, registra motivo y libera agenda+técnico',
  })
  @ApiParam({ name: 'codigo', example: 'ORD-DEMO-2001' })
  @ApiResponse({ status: 200 })
  @ApiBody({ type: AnularOrdenDto })
  async anular(@Param('codigo') codigo: string, @Body() body: AnularOrdenDto) {
    return await this.agendaService.anularPorCodigo(codigo, body);
  }
}
