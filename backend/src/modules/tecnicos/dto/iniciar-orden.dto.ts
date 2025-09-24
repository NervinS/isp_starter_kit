// src/modules/tecnicos/dto/iniciar-orden.dto.ts
import { IsOptional, IsString, MaxLength } from 'class-validator';

export class IniciarOrdenDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  notaInicio?: string;
}
