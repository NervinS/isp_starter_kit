// src/modules/inventario/dto/movimiento.dto.ts
import {
  IsString, IsOptional, IsIn, IsUUID, IsInt, Min, ValidateIf, IsNumber,
} from 'class-validator';
import { Type } from 'class-transformer';

export type TipoMovimiento = 'ingreso' | 'egreso' | 'transferencia' | 'ajuste';
export type ModoAjuste = 'set' | 'delta';

export class MovimientoDto {
  @IsString()
  idempotencyKey!: string;

  @IsIn(['ingreso', 'egreso', 'transferencia', 'ajuste'])
  tipo!: TipoMovimiento;

  @ValidateIf(o => o.tipo === 'egreso' || o.tipo === 'transferencia')
  @IsUUID()
  @IsOptional()
  almacenOrigenId?: string;

  @ValidateIf(o => o.tipo === 'ingreso' || o.tipo === 'transferencia')
  @IsUUID()
  @IsOptional()
  almacenDestinoId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  materialIdInt?: number;

  @IsOptional()
  @IsString()
  materialId?: string;

  @ValidateIf(o => o.tipo === 'ingreso' || o.tipo === 'egreso' || o.tipo === 'transferencia')
  @Type(() => Number)
  @IsNumber()
  @Min(0.000001)
  @IsOptional()
  cantidad?: number;

  @ValidateIf(o => o.tipo === 'ajuste')
  @Type(() => Number)
  @IsNumber()
  @IsOptional()
  cantidadSigned?: number;

  @IsOptional()
  @IsIn(['set', 'delta'])
  modoAjuste?: ModoAjuste;

  @IsOptional()
  @IsString()
  motivo?: string;

  @IsOptional()
  @IsString()
  nota?: string;

  @IsOptional()
  @IsString()
  userId?: string;

  @IsOptional()
  @IsString()
  refExterna?: string;

  @IsOptional()
  @IsString()
  evidenciaKey?: string;
}
