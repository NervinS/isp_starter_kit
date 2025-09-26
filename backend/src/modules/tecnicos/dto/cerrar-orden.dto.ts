// src/modules/tecnicos/dto/cerrar-orden.dto.ts
import { IsArray, IsOptional, IsString, ValidateNested, IsNumber } from 'class-validator';
import { Type } from 'class-transformer';

class MaterialItemDto {
  @IsOptional()
  @IsNumber()
  materialId?: number;        // compat

  @IsOptional()
  @IsNumber()
  materialIdInt?: number;     // compat

  @IsNumber()
  cantidad!: number;
}

export class CerrarOrdenDto {
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => MaterialItemDto)
  materiales?: MaterialItemDto[];

  // Firma en Data URL (base64)
  @IsOptional()
  @IsString()
  firmaBase64?: string;

  // Evidencias en Data URL (base64)
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  evidenciasBase64?: string[];
}
