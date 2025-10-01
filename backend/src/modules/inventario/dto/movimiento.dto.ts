// src/modules/inventario/dto/movimiento.dto.ts
import {
  IsString,
  IsOptional,
  IsIn,
  IsUUID,
  IsInt,
  Min,
  ValidateIf,
  IsNumber,
} from 'class-validator';
import { Type } from 'class-transformer';

export type TipoMovimiento = 'ingreso' | 'egreso' | 'transferencia' | 'ajuste';
export type ModoAjuste = 'set' | 'delta';

export class MovimientoDto {
  // Idempotencia: opcional para endpoints internos; el service la autogenera si falta.
  @IsOptional()
  @IsString()
  idempotencyKey?: string;

  @IsIn(['ingreso', 'egreso', 'transferencia', 'ajuste'])
  tipo!: TipoMovimiento;

  // ==== Almacenes según tipo ====
  @ValidateIf(o => o.tipo === 'egreso' || o.tipo === 'transferencia')
  @IsUUID()
  @IsOptional()
  almacenOrigenId?: string;

  @ValidateIf(o => o.tipo === 'ingreso' || o.tipo === 'transferencia')
  @IsUUID()
  @IsOptional()
  almacenDestinoId?: string;

  // ==== Material ====
  // Preferido: INTEGER
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  materialIdInt?: number;

  // Fallback: string parseable
  @IsOptional()
  @IsString()
  materialId?: string;

  // ==== Cantidades ====
  // Para ingreso/egreso/transferencia: > 0
  @ValidateIf(o => o.tipo === 'ingreso' || o.tipo === 'egreso' || o.tipo === 'transferencia')
  @Type(() => Number)
  @IsNumber()
  @Min(0.000001)
  @IsOptional()
  cantidad?: number;

  // Para ajuste
  @ValidateIf(o => o.tipo === 'ajuste')
  @Type(() => Number)
  @IsNumber()
  @IsOptional()
  cantidadSigned?: number;

  // Para "ajuste": modo set/delta
  @IsOptional()
  @IsIn(['set', 'delta'])
  modoAjuste?: ModoAjuste;

  // ==== Metadatos opcionales ====
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
