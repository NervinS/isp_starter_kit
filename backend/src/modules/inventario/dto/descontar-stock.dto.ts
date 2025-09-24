// src/modules/inventario/dto/descontar-stock.dto.ts
import { IsUUID, IsNumber, Min } from 'class-validator';
import { Transform } from 'class-transformer';

export class DescontarStockDto {
  @IsUUID('4')
  materialId!: string;

  @Transform(({ value }) => Number(value))
  @IsNumber()
  @Min(0.000001, { message: 'cantidad debe ser > 0' })
  cantidad!: number;
}
