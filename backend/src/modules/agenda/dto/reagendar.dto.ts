// src/modules/agenda/dto/reagendar.dto.ts
import { IsDateString, IsIn, IsOptional, IsString } from 'class-validator';

export class ReagendarDto {
  @IsDateString()
  fecha!: string;

  @IsString()
  @IsIn(['am', 'pm'])
  turno!: 'am' | 'pm';

  // preferido: código del catálogo (p.ej. "cliente-ausente")
  @IsOptional()
  @IsString()
  motivoCodigo?: string;

  // opcional: texto libre (fallback legacy)
  @IsOptional()
  @IsString()
  motivo?: string;
}
