// src/modules/agenda/dto/asignar-orden.dto.ts
import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsIn, IsDateString, IsNotEmpty } from 'class-validator';

export class AsignarOrdenDto {
  @ApiProperty({ example: 'uuid-del-tecnico' })
  @IsString() @IsNotEmpty()
  tecnicoId!: string;

  @ApiProperty({ example: '2025-09-17', description: 'YYYY-MM-DD' })
  @IsDateString()
  fecha!: string;

  @ApiProperty({ example: 'am', enum: ['am', 'pm'] })
  @IsString() @IsIn(['am','pm'])
  turno!: 'am' | 'pm';
}
