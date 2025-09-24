// src/modules/agenda/dto/reagendar-orden.dto.ts
import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsIn, IsDateString } from 'class-validator';

export class ReagendarOrdenDto {
  @ApiProperty({ example: '2025-09-18', description: 'YYYY-MM-DD' })
  @IsDateString()
  fecha!: string;

  @ApiProperty({ example: 'pm', enum: ['am', 'pm'] })
  @IsString() @IsIn(['am','pm'])
  turno!: 'am' | 'pm';
}
