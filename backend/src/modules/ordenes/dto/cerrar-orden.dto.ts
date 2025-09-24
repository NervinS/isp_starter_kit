import { IsArray, IsInt, IsOptional, IsString, IsUUID, Min, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class LineaMaterialDto {
  @IsInt()
  @Min(1)
  materialIdInt!: number;

  @IsInt()
  @Min(1)
  cantidad!: number;
}

export class CerrarOrdenDto {
  @IsUUID()
  tecnicoId!: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => LineaMaterialDto)
  materiales!: LineaMaterialDto[];

  @IsOptional()
  @IsArray()
  evidenciasBase64?: string[];

  @IsOptional()
  @IsString()
  firmaBase64?: string | null;
}
