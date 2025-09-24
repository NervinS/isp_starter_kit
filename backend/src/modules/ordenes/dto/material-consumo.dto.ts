import { IsUUID, IsNumber, Min } from 'class-validator';

export class MaterialConsumoDto {
  @IsUUID('4', { message: 'materiales.*.materialId debe ser UUID v4' })
  materialId!: string;

  @IsNumber({}, { message: 'materiales.*.cantidad debe ser número' })
  @Min(0.0001, { message: 'materiales.*.cantidad debe ser mayor que 0' })
  cantidad!: number;

  @IsNumber({}, { message: 'materiales.*.precioUnitario debe ser número' })
  @Min(0, { message: 'materiales.*.precioUnitario no puede ser negativo' })
  precioUnitario!: number;
}
