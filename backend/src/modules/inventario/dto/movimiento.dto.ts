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

export type TipoMovimiento = 'ingreso' | 'egreso' | 'ajuste' | 'traslado' | 'transferencia';
export type ModoAjuste = 'set' | 'delta';

export class MovimientoDto {
  // ===== Idempotencia (opcional) =====
  @IsOptional()
  @IsString()
  idempotencyKey?: string;

  // ===== Tipo =====
  @IsIn(['ingreso', 'egreso', 'ajuste', 'traslado', 'transferencia'])
  tipo!: TipoMovimiento;

  // ===== Almacenes (solo para traslado/transferencia) =====
  @ValidateIf(o => o.tipo === 'traslado' || o.tipo === 'transferencia')
  @IsUUID()
  @IsOptional()
  almacenOrigenId?: string;

  @ValidateIf(o => o.tipo === 'traslado' || o.tipo === 'transferencia')
  @IsUUID()
  @IsOptional()
  almacenDestinoId?: string;

  // ===== Material =====
  // Opción preferida: ID numérico (int)
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  materialIdInt?: number;

  // Opción alternativa: ID como string (parseable)
  @IsOptional()
  @IsString()
  materialId?: string;

  // ===== Cantidad =====
  // Un único campo para todos los tipos:
  // - ingreso/egreso/traslado/transferencia: > 0  (el service ya valida > 0)
  // - ajuste (modo "set"): >= 0                 (el service calcula delta)
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  cantidad?: number;

  // ===== Ajuste =====
  @IsOptional()
  @IsIn(['set', 'delta'])
  modoAjuste?: ModoAjuste;

  // ===== Metadatos opcionales =====
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
