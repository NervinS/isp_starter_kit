// src/modules/agenda/dto/anular-orden.dto.ts
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MinLength } from 'class-validator';

export class AnularOrdenDto {
  @ApiProperty({ example: 'No hay cobertura' })
  @IsString() @MinLength(3)
  motivo!: string;

  @ApiPropertyOptional({ example: 'SIN_COBERTURA' })
  @IsOptional() @IsString()
  motivoCodigo?: string;
}
