// src/modules/agenda/dto/cancelar-orden.dto.ts
import { IsOptional, IsString, MaxLength } from 'class-validator';

export class CancelarOrdenDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  motivo?: string;
}
