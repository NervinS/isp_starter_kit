// src/modules/inventario/dto/tecnico-stock.dto.ts
import { IsInt, Min } from 'class-validator';

export class TecnicoStockDto {
  @IsInt()
  @Min(1)
  materialId: number;   // <— ENTERO

  @IsInt()
  @Min(1)
  cantidad: number;     // <— ENTERO (>0)
}
