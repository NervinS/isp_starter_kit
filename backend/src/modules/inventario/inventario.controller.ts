// src/modules/inventario/inventario.controller.ts
import {
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Body,
  BadRequestException,
} from '@nestjs/common';
import { ApiOperation, ApiParam, ApiResponse, ApiTags } from '@nestjs/swagger';
import { InventarioService } from './inventario.service';
import { DescontarStockDto } from './dto/descontar-stock.dto';

@ApiTags('Inventario')
@Controller('inventario')
export class InventarioController {
  constructor(private readonly inventarioService: InventarioService) {}

  // GET /v1/inventario/tecnicos/:tecnicoId/stock
  @Get('tecnicos/:tecnicoId/stock')
  @ApiOperation({
    summary: 'Listar stock actual del técnico',
    description:
      'Devuelve el stock por material del técnico indicado (materialId, codigo, nombre, cantidad).',
  })
  @ApiParam({
    name: 'tecnicoId',
    description: 'UUID del técnico',
    example: 'd1e89d6f-3d79-40ed-8605-537b9ab1e007',
  })
  @ApiResponse({ status: 200, description: 'Listado de stock del técnico.' })
  async listarStockDeTecnico(
    @Param('tecnicoId', new ParseUUIDPipe()) tecnicoId: string,
  ) {
    return this.inventarioService.listarStockDeTecnico(tecnicoId);
  }

  // POST /v1/inventario/tecnicos/:tecnicoId/descontar
  @Post('tecnicos/:tecnicoId/descontar')
  @ApiOperation({
    summary: 'Descontar stock del técnico',
    description:
      'Descuenta cantidad del material en el stock del técnico. Valida existencia y cantidad suficiente.',
  })
  @ApiParam({
    name: 'tecnicoId',
    description: 'UUID del técnico',
    example: 'd1e89d6f-3d79-40ed-8605-537b9ab1e007',
  })
  @ApiResponse({ status: 201, description: 'Descuento aplicado.' })
  async descontarStock(
    @Param('tecnicoId', new ParseUUIDPipe()) tecnicoId: string,
    @Body() body: DescontarStockDto,
  ) {
    // En tu DTO actual materialId llega como string (uuid). En BD materiales.id es INTEGER.
    // Convertimos con validación estricta a entero positivo.
    const materialId = Number((body as any).materialId);
    if (!Number.isInteger(materialId) || materialId <= 0) {
      throw new BadRequestException(
        'materialId debe ser un número entero positivo.',
      );
    }

    const cantidad = Number(body.cantidad);
    if (!Number.isInteger(cantidad) || cantidad <= 0) {
      throw new BadRequestException(
        'cantidad debe ser un número entero positivo.',
      );
    }

    const resultado = await this.inventarioService.descontarStock(
      tecnicoId,
      materialId,
      cantidad,
    );

    return {
      ok: true,
      ...resultado,
    };
  }
}
