// src/modules/inventario/dto/agregar-stock.dto.ts
import { IsInt, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class AgregarStockDto {
  @ApiProperty({ type: Number, example: 1 })
  @IsInt()
  @Min(1)
  materialId: number;

  @ApiProperty({ type: Number, example: 2 })
  @IsInt()
  @Min(1)
  cantidad: number;
}
