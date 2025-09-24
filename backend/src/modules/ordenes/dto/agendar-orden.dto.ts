// src/modules/ordenes/dto/agendar-orden.dto.ts
import { IsISO8601, IsOptional, IsString, IsUUID } from 'class-validator';

export class AgendarOrdenDto {
  @IsUUID('4', { message: 'tecnicoId debe ser un UUID válido' })
  tecnicoId!: string;

  // Fecha ISO-8601 (YYYY-MM-DD); si usas date-only, está OK
  @IsISO8601({ strict: true }, { message: 'fecha debe ser ISO-8601 (YYYY-MM-DD)' })
  fecha!: string;

  @IsString()
  turno!: string; // 'manana' | 'tarde' | 'noche' | custom

  @IsOptional()
  @IsString()
  notas?: string;
}

export class AgendarOrdenPatchDto {
  // Todos opcionales para permitir reagendar o reasignar parcialmente
  @IsOptional()
  @IsUUID('4', { message: 'tecnicoId debe ser un UUID válido' })
  tecnicoId?: string | null;

  @IsOptional()
  @IsISO8601({ strict: true }, { message: 'fecha debe ser ISO-8601 (YYYY-MM-DD)' })
  fecha?: string | null;

  @IsOptional()
  @IsString()
  turno?: string | null;

  @IsOptional()
  @IsString()
  notas?: string | null;
}
