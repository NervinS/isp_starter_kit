// src/modules/ordenes/dto/cerrar-completo.dto.ts
import { IsArray, ArrayMinSize, IsOptional, IsString, ValidateNested, IsInt, Min } from 'class-validator';
import { Type, Transform } from 'class-transformer';

class MaterialLineaDto {
  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(1)
  materialId!: number;

  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(1)
  cantidad!: number;

  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(0)
  precioUnitario!: number;
}

export class CerrarCompletoDto {
  @IsOptional() @IsArray() fotos?: string[];
  @IsArray() @ArrayMinSize(1) @ValidateNested({ each: true }) @Type(() => MaterialLineaDto)
  materiales!: MaterialLineaDto[];
  @IsOptional() @IsString() notas?: string;

  // snapshot técnico opcional (según tipo de orden)
  @IsOptional() snapshot?: Record<string, any>;
}
