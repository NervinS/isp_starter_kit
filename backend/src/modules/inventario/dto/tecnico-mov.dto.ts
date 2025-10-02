// src/modules/inventario/dto/tecnico-mov.dto.ts
import { IsInt, Min, IsOptional, IsString, ValidateIf } from 'class-validator';
import { Type } from 'class-transformer';

export class TecnicoMovDto {
  @ValidateIf(o => o.materialId !== undefined)
  @IsString()
  materialId?: string;

  @ValidateIf(o => o.materialIdInt !== undefined)
  @Type(() => Number)
  @IsInt()
  @Min(1)
  materialIdInt?: number;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  cantidad!: number;

  @IsOptional()
  @IsString()
  nota?: string;
}
