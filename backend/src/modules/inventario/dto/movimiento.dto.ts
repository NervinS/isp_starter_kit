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

export class MovimientoDto {
  @IsString()
  idempotencyKey!: string;

  @IsIn(['ingreso', 'egreso', 'transferencia', 'ajuste'])
  tipo!: TipoMovimiento;

  // ==== Almacenes segun tipo ====
  @ValidateIf(o => o.tipo === 'egreso' || o.tipo === 'transferencia')
  @IsUUID()
  almacenOrigenId?: string;

  @ValidateIf(o => o.tipo === 'ingreso' || o.tipo === 'transferencia')
  @IsUUID()
  almacenDestinoId?: string;

  // ==== Material ====
  // Preferido: INTEGER
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  materialIdInt?: number;

  // Fallback: string parseable -> lo normalizamos en el controller
  @IsOptional()
  @IsString()
  materialId?: string;

  // ==== Cantidades ====
  // Para ingreso/egreso/transferencia: > 0
  @ValidateIf(o => o.tipo === 'ingreso' || o.tipo === 'egreso' || o.tipo === 'transferencia')
  @Type(() => Number)
  @IsNumber()
  @Min(0.000001)
  cantidad?: number;

  // Para ajuste: cantidad con signo (si usas esta modalidad en el servicio)
  @ValidateIf(o => o.tipo === 'ajuste')
  @Type(() => Number)
  @IsNumber()
  cantidadSigned?: number;

  // ==== Metadatos ====
  @IsOptional()
  @IsString()
  motivo?: string;

  @IsOptional()
  @IsString()
  refExterna?: string;

  @IsOptional()
  @IsString()
  evidenciaKey?: string;
}
