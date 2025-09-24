// src/modules/ordenes/dto/linea-material.dto.ts
import { IsInt, Min, IsNumber, IsOptional, IsString } from 'class-validator';
import { Transform } from 'class-transformer';

export class LineaMaterialDto {
  // opción A (preferida): materialId INTEGER (id de tabla materiales)
  @Transform(({ value }) => Number(value))
  @IsInt({ message: 'materialId debe ser entero' })
  @Min(1)
  materialId!: number;

  // opción B (alternativa): permitir código de material si no te pasan id
  @IsOptional()
  @IsString()
  materialCodigo?: string;

  @Transform(({ value }) => Number(value))
  @IsNumber({}, { message: 'cantidad debe ser numérico' })
  @Min(0.000001, { message: 'cantidad debe ser > 0' })
  cantidad!: number;

  @Transform(({ value }) => Number(value))
  @IsNumber({}, { message: 'precioUnitario debe ser numérico' })
  @Min(0, { message: 'precioUnitario no puede ser negativo' })
  precioUnitario!: number;
}
