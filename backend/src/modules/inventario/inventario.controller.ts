// src/modules/inventario/inventario.controller.ts
import {
  Body,
  Controller,
  Get,
  Param,
  Post,
} from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { InventarioService } from './inventario.service';
import {
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Min,
  ValidateIf,
} from 'class-validator';
import { Transform } from 'class-transformer';

function normalizeMaterialId(v: unknown): string {
  if (typeof v === 'number') return String(v);
  if (typeof v === 'string') return v.trim();
  throw new Error('materialId inválido');
}

class MovimientoTecnicoDto {
  @Transform(({ value }) => normalizeMaterialId(value))
  @IsString()
  @IsNotEmpty()
  materialId!: string;

  @Transform(({ value }) => (typeof value === 'string' ? Number(value) : value))
  @IsNumber()
  @Min(1)
  cantidad!: number;

  @ValidateIf((o) => o?.nota !== undefined)
  @IsString()
  @IsOptional()
  nota?: string;
}

@ApiTags('Inventario')
// ⚠️ Importante: SIN /v1 aquí. El globalPrefix('v1') ya lo agrega.
// Resultado final de las rutas: /v1/inventario/...
@Controller('inventario')
export class InventarioController {
  constructor(private readonly inv: InventarioService) {}

  // Stock por técnico
  @Get('/tecnicos/:tecnicoId/stock')
  async stockTecnico(@Param('tecnicoId') tecnicoId: string) {
    return this.inv.getStockTecnico(tecnicoId);
  }

  // Agregar stock a un técnico
  @Post('/tecnicos/:tecnicoId/agregar')
  async agregarStockTecnico(
    @Param('tecnicoId') tecnicoId: string,
    @Body() dto: MovimientoTecnicoDto,
  ) {
    return this.inv.crearMovimiento({
      tipo: 'ingreso',
      tecnicoId,
      materialId: dto.materialId,
      cantidad: dto.cantidad,
      nota: dto.nota,
    });
  }

  // Descontar stock a un técnico
  @Post('/tecnicos/:tecnicoId/descontar')
  async descontarStockTecnico(
    @Param('tecnicoId') tecnicoId: string,
    @Body() dto: MovimientoTecnicoDto,
  ) {
    return this.inv.crearMovimiento({
      tipo: 'egreso',
      tecnicoId,
      materialId: dto.materialId,
      cantidad: dto.cantidad,
      nota: dto.nota,
    });
  }

  // Ajustar stock a un técnico (setear cantidad exacta)
  @Post('/tecnicos/:tecnicoId/ajustar')
  async ajustarStockTecnico(
    @Param('tecnicoId') tecnicoId: string,
    @Body() dto: MovimientoTecnicoDto,
  ) {
    return this.inv.crearMovimiento({
      tipo: 'ajuste',
      tecnicoId,
      materialId: dto.materialId,
      cantidad: dto.cantidad,
      nota: dto.nota,
      modoAjuste: 'set',
    });
  }

  // Endpoints generales
  @Get('/stock')
  async stockGlobal() {
    return this.inv.getStockGlobal();
  }

  @Get('/kardex')
  async kardex() {
    return this.inv.getKardex();
  }

  // Crear movimiento genérico
  @Post('/movimientos')
  async crearMovimiento(@Body() body: any) {
    return this.inv.crearMovimiento(body);
  }
}
