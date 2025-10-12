// src/modules/inventario/dto/transferir-mov.dto.ts
import { ApiPropertyOptional, ApiProperty } from '@nestjs/swagger';
import { IsNumber, IsPositive, IsUUID, IsOptional, IsString } from 'class-validator';
import { Type } from 'class-transformer';

export class TransferirMovDto {
  @ApiProperty({ example: 3 })
  @Type(() => Number)
  @IsNumber()
  @IsPositive()
  materialId!: number;

  @ApiProperty({ example: 2 })
  @Type(() => Number)
  @IsNumber()
  @IsPositive()
  cantidad!: number;

  @ApiProperty({
    description: 'UUID del almacén origen',
    example: '9191e7cb-de60-4e29-917f-f4f005963863',
  })
  @IsUUID()
  fromAlmacenId!: string;

  @ApiProperty({
    description: 'UUID del almacén destino',
    example: '62ebd37f-44c4-499d-b9ed-7bee75b09275',
  })
  @IsUUID()
  toAlmacenId!: string;

  @ApiPropertyOptional({
    description: 'Clave de idempotencia (también se acepta por header Idempotency-Key)',
    example: 'idem-mov-abc',
  })
  @IsOptional()
  @IsString()
  idempotencyKey?: string;

  @ApiPropertyOptional({ description: 'Nota libre', example: 'transferencia manual' })
  @IsOptional()
  @IsString()
  nota?: string;
}
