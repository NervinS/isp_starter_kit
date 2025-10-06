// src/modules/inventario/dto/ajuste-stock.dto.ts
import { IsInt, Min, IsIn, IsOptional, IsString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class AjusteStockDto {
  @ApiProperty({ type: Number, example: 3 })
  @IsInt()
  @Min(1)
  materialId: number;

  @ApiProperty({ type: Number, example: 2 })
  @IsInt()
  @Min(1)
  cantidad: number;

  @ApiProperty({ enum: ['mas', 'menos'], example: 'menos' })
  @IsIn(['mas', 'menos'])
  signo: 'mas' | 'menos';

  @ApiProperty({ type: String, required: false, example: 'ajuste de inventario' })
  @IsOptional()
  @IsString()
  nota?: string;
}
