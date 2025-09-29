// src/modules/inventario/inventario.controller.ts
import { Controller, Get, Post, Param, Body, Query, Req } from '@nestjs/common';
import { InventarioService } from './inventario.service';

// DTOs existentes (técnicos)
import { DescontarStockDto } from './dto/descontar-stock.dto';
import { AgregarStockDto } from './dto/agregar-stock.dto';
import { AjusteStockDto } from './dto/ajuste-stock.dto';

// ✅ DTO corporativo con class-validator
import { MovimientoDto } from './dto/movimiento.dto';

@Controller('inventario') // recuerda: en runtime será /v1/inventario/... por el globalPrefix
export class InventarioController {
  constructor(private readonly svc: InventarioService) {}

  // ==========================
  //   RUTAS EXISTENTES (Técnico)
  // ==========================

  @Get('tecnicos/:tecnicoId/stock')
  async listarStockTecnico(@Param('tecnicoId') tecnicoId: string) {
    return this.svc.listarStockDeTecnico(tecnicoId);
  }

  @Post('tecnicos/:tecnicoId/descontar')
  async descontarStockTecnico(
    @Param('tecnicoId') tecnicoId: string,
    @Body() dto: DescontarStockDto,
  ) {
    const { materialId, cantidad } = dto;
    return this.svc.descontarStock(tecnicoId, Number(materialId), Number(cantidad));
  }

  // (Opcionales expuestos)
  @Post('tecnicos/:tecnicoId/agregar')
  async agregarStockTecnico(
    @Param('tecnicoId') tecnicoId: string,
    @Body() dto: AgregarStockDto,
  ) {
    const { materialId, cantidad } = dto;
    await this.svc.agregarStock(tecnicoId, Number(materialId), Number(cantidad));
    return { ok: true };
  }

  @Post('tecnicos/:tecnicoId/ajustar')
  async ajustarStockTecnico(
    @Param('tecnicoId') tecnicoId: string,
    @Body() dto: AjusteStockDto,
  ) {
    const { materialId, cantidad } = dto;
    await this.svc.ajustarStock(tecnicoId, Number(materialId), Number(cantidad));
    return { ok: true };
  }

  // ==========================
  //   NUEVAS RUTAS CORPORATIVAS
  // ==========================

  /** Crear movimiento corporativo (ingreso/egreso/transferencia/ajuste). */
  @Post('movimientos')
  async crearMovimiento(@Body() dto: MovimientoDto, @Req() req: any) {
    // Normaliza fallback: materialId(string) -> materialIdInt(number)
    const materialIdInt =
      dto.materialIdInt ?? (dto.materialId ? Number(dto.materialId) : undefined);

    const dtoNorm = { ...dto, materialIdInt };
    const userId = req?.user?.sub ?? undefined;

    return this.svc.crearMovimiento(dtoNorm as any, userId);
  }

  /** Stock corporativo (stock_almacen). */
  @Get('stock')
  async stockCorp(
    @Query('scope') scope?: 'principal' | 'tecnico',
    @Query('id') id?: string,
  ) {
    return this.svc.getStockCorporativo(scope, id);
  }

  /** Kardex corporativo (v_kardex). */
  @Get('kardex')
  async kardexCorp(
    @Query('materialIdInt') materialIdInt: string,
    @Query('almacenId') almacenId?: string,
    @Query('desde') desde?: string,
    @Query('hasta') hasta?: string,
  ) {
    const mid = Number(materialIdInt);
    return this.svc.getKardex(mid, almacenId, desde, hasta);
  }
}
