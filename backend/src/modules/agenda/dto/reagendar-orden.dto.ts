// src/modules/agenda/dto/reagendar-orden.dto.ts
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsDateString, IsIn, IsOptional, IsString, Length } from 'class-validator';

export class ReagendarOrdenDto {
  @ApiProperty({ example: '2025-09-26', description: 'Fecha nueva (YYYY-MM-DD)' })
  @IsDateString()
  fecha!: string;

  @ApiProperty({ example: 'pm', enum: ['am', 'pm'] })
  @IsString()
  @IsIn(['am', 'pm'])
  turno!: 'am' | 'pm';

  @ApiPropertyOptional({ example: 'cliente-ausente', description: 'Código del catálogo' })
  @IsOptional()
  @IsString()
  @Length(1, 100)
  motivoCodigo?: string;

  @ApiPropertyOptional({ example: 'Cliente pidió mover la cita', description: 'Texto libre' })
  @IsOptional()
  @IsString()
  @Length(1, 200)
  motivo?: string;
}
