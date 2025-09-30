// src/modules/inventario/dto/inventario.dto.ts
import { IsInt, IsOptional, IsUUID, Min } from 'class-validator';

export class MovimientoDto {
  // NUEVO: aceptar id entero del catálogo de materiales
  @IsOptional() @IsInt() materialIdInt?: number;

  // (si alguna vez usas por uuid del material, lo dejas opcional)
  @IsOptional() @IsUUID() materialId?: string;

  @IsInt() @Min(1) cantidad!: number;
}
