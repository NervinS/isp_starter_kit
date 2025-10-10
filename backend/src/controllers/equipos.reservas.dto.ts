// src/controllers/equipos.reservas.dto.ts
import { IsUUID, IsInt, Min, IsOptional } from 'class-validator';
import { Type } from 'class-transformer';

export class ReservarDto {
  @IsUUID()
  id!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  tecnicoId!: number;
}

export class LiberarDto {
  @IsUUID()
  id!: string;
}

export class ReservasQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  tecnicoId?: number;
}
