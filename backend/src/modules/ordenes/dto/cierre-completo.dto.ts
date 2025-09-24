import { IsOptional, IsString, IsArray, ValidateNested, IsUUID } from 'class-validator';
import { Type } from 'class-transformer';
import { MaterialConsumoDto } from './material-consumo.dto';

export class CierreCompletoDto {
  @IsOptional()
  @IsString({ message: 'tecnicoCodigo debe ser string' })
  tecnicoCodigo?: string;

  @IsArray({ message: 'materiales debe ser arreglo' })
  @ValidateNested({ each: true })
  @Type(() => MaterialConsumoDto)
  materiales!: MaterialConsumoDto[];

  @IsOptional()
  @IsString()
  notas?: string;
}
