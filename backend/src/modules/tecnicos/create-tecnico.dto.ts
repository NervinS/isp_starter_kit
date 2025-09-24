// src/modules/tecnicos/create-tecnico.dto.ts
import { ApiProperty } from '@nestjs/swagger';

export class CreateTecnicoDto {
  @ApiProperty()
  codigo!: string;

  @ApiProperty({ required: false })
  nombre?: string;

  @ApiProperty({ required: false })
  telefono?: string;
}
