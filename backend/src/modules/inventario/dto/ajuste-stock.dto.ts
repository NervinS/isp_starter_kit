// src/modules/inventario/dto/ajuste-stock.dto.ts
import { IsInt, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class AjusteStockDto {
  @ApiProperty({ type: Number, example: 1 })
  @IsInt()
  @Min(1)
  materialId: number;

  @ApiProperty({ type: Number, example: 2 })
  @IsInt()
  @Min(1)
  cantidad: number;
}
