// src/modules/tecnicos/dto/crear-tecnico.dto.ts
import { IsBoolean, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class CrearTecnicoDto {
  @IsString()
  @MinLength(3)
  @MaxLength(50)
  nombre!: string;

  // opcional: si tu modelo usa “codigo” (ej. TEC-0006)
  @IsOptional()
  @IsString()
  @MaxLength(20)
  codigo?: string;

  @IsOptional()
  @IsBoolean()
  activo?: boolean;
}
