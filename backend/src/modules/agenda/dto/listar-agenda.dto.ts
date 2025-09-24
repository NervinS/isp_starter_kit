// src/modules/agenda/dto/listar-agenda.dto.ts
import { IsIn, IsOptional, IsString, IsISO8601 } from 'class-validator';

export class ListarAgendaQueryDto {
  @IsIn(['creada', 'agendada'])
  estado!: 'creada' | 'agendada';

  @IsOptional()
  @IsString()
  municipio?: string; // e.g. 'BARRANQUILLA'

  @IsOptional()
  @IsString()
  q?: string; // texto libre: nombre, documento, direccion, barrio, codigo

  @IsOptional()
  @IsISO8601()
  desde?: string; // ISO: 2025-09-10T00:00:00-05:00

  @IsOptional()
  @IsISO8601()
  hasta?: string; // ISO
}
