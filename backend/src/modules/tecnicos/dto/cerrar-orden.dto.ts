// src/modules/tecnicos/dto/cerrar-orden.dto.ts
import {
  IsArray,
  ArrayMaxSize,
  IsInt,
  Min,
  IsObject,
  IsOptional,
  IsString,
  MaxLength,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';

export class MaterialItemDto {
  @IsString()
  @MaxLength(64)
  materialId!: string;

  @IsInt()
  @Min(1)
  cantidad!: number;
}

export class CerrarOrdenDto {
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  observaciones?: string;

  /**
   * Datos dinámicos del formulario (INS: mac_ont, potencia_rx, etc / MAN: causa, accion, etc)
   */
  @IsOptional()
  @IsObject()
  form?: Record<string, any>;

  /**
   * Claves/urls de fotos. Ej.: ["key://pre.jpg","key://post.jpg"]
   */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @IsString({ each: true })
  fotos?: string[];

  /**
   * Materiales usados (INS suele requerir al menos uno)
   */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => MaterialItemDto)
  materiales?: MaterialItemDto[];

  /**
   * Firma capturada (key/URL en tu storage). Se guardará en ordenes.firma_key.
   */
  @IsOptional()
  @IsString()
  @MaxLength(256)
  firmaKey?: string;
}
