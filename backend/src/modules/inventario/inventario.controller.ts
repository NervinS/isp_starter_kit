// src/modules/inventario/inventario.controller.ts
import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  Get,
  Headers,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { InventarioService, MovimientoInput } from './inventario.service';
import { AjusteStockDto } from './dto/ajuste-stock.dto';

@ApiTags('Inventario')
// ⚠️ IMPORTANTE: sin /v1 aquí. El /v1 lo pone el globalPrefix en main.ts
@Controller('inventario')
export class InventarioController {
  constructor(private readonly inv: InventarioService) {}

  // ---------- Lecturas ----------
  @Get('stock/almacen/:codigo')
  @ApiOperation({ summary: 'Stock por almacén (código)' })
  async stockPorAlmacen(@Param('codigo') codigo: string, @Query('materialId') materialId?: string) {
    const mid = materialId ? Number(materialId) : undefined;
    return this.inv.getStockPorAlmacenCodigo({ almacenCodigo: codigo, materialId: mid });
  }

  @Get('tecnicos/:id/stock')
  @ApiOperation({ summary: 'Stock de almacén técnico TEC-{id}' })
  async stockTecnico(@Param('id') id: string) {
    return this.inv.getStockTecnico(id);
  }

  @Get('kardex')
  @ApiOperation({ summary: 'Últimos movimientos (kardex)' })
  async kardex(@Query('limit') limit?: string) {
    const lim = limit ? Number(limit) : undefined;
    return this.inv.getKardex(lim);
  }

  // ---------- Mutaciones genéricas ----------
  @Post('movimientos')
  @ApiOperation({
    summary: 'Crear movimiento (ingreso/egreso/traslado/ajuste)',
    description:
      "Para traslado puedes enviar tipo='traslado' o 'transferencia' (se normaliza a 'traslado').",
  })
  async crearMovimiento(
    @Body() body: MovimientoInput,
    @Headers('idempotency-key') idempotencyKey?: string,
  ) {
    try {
      return await this.inv.crearMovimiento(body, idempotencyKey); // 201 por defecto
    } catch (e: any) {
      if (typeof e?.message === 'string' && /saldo insuficiente/i.test(e.message)) {
        throw new ConflictException({ message: e.message, code: 'INSUFFICIENT_STOCK' });
      }
      throw new BadRequestException(e?.message ?? 'Error al crear movimiento');
    }
  }

  // ---------- Acciones de técnico ----------
  @Post('tecnicos/:id/agregar')
  @ApiOperation({ summary: 'Trasladar desde MAIN a TEC-{id}' })
  async agregarTecnico(
    @Param('id') id: string,
    @Body() dto: { materialId: number | string; cantidad: number | string; nota?: string | null },
    @Headers('idempotency-key') idempotencyKey?: string,
  ) {
    try {
      return await this.inv.agregarATecnico(
        {
          tecnicoId: id,
          materialId: dto.materialId,
          cantidad: dto.cantidad,
          nota: dto.nota ?? null,
        },
        idempotencyKey,
      );
    } catch (e: any) {
      if (typeof e?.message === 'string' && /saldo insuficiente/i.test(e.message)) {
        throw new ConflictException({ message: e.message, code: 'INSUFFICIENT_STOCK' });
      }
      throw new BadRequestException(e?.message ?? 'Error al agregar a técnico');
    }
  }

  @Post('tecnicos/:id/descontar')
  @ApiOperation({ summary: 'Devolver desde TEC-{id} a MAIN' })
  async descontarTecnico(
    @Param('id') id: string,
    @Body() dto: { materialId: number | string; cantidad: number | string; nota?: string | null },
    @Headers('idempotency-key') idempotencyKey?: string,
  ) {
    try {
      return await this.inv.descontarATecnico(
        {
          tecnicoId: id,
          materialId: dto.materialId,
          cantidad: dto.cantidad,
          nota: dto.nota ?? null,
        },
        idempotencyKey,
      );
    } catch (e: any) {
      if (typeof e?.message === 'string' && /saldo insuficiente/i.test(e.message)) {
        throw new ConflictException({ message: e.message, code: 'INSUFFICIENT_STOCK' });
      }
      throw new BadRequestException(e?.message ?? 'Error al descontar a técnico');
    }
  }

  @Post('tecnicos/:id/ajustar')
  @ApiOperation({
    summary: 'Ajuste sobre TEC-{id}',
    description: "signo='mas' suma stock, signo='menos' descuenta stock",
  })
  async ajustarTecnico(
    @Param('id') id: string,
    @Body() dto: AjusteStockDto & { signo: 'mas' | 'menos'; nota?: string | null },
    @Headers('idempotency-key') idempotencyKey?: string,
  ) {
    try {
      return await this.inv.ajustarTecnico(
        {
          tecnicoId: id,
          materialId: dto.materialId,
          cantidad: dto.cantidad,
          signo: dto.signo,
          nota: dto.nota ?? null,
        },
        idempotencyKey,
      );
    } catch (e: any) {
      if (typeof e?.message === 'string' && /saldo insuficiente/i.test(e.message)) {
        throw new ConflictException({ message: e.message, code: 'INSUFFICIENT_STOCK' });
      }
      throw new BadRequestException(e?.message ?? 'Error al ajustar técnico');
    }
  }
}
