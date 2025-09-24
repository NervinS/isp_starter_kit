// src/modules/tecnicos/dto/solicitar-reagenda.dto.ts
import {
  IsUUID,
  IsOptional,
  IsString,
  MaxLength,
  IsIn,
  IsDateString,
} from 'class-validator';

export class SolicitarReagendaDto {
  @IsOptional()
  @IsUUID('4', { message: 'motivoId debe ser UUID v4' })
  motivoId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(280, { message: 'comentario máximo 280 caracteres' })
  comentario?: string;

  @IsOptional()
  @IsDateString({}, { message: 'fechaDeseada debe ser YYYY-MM-DD' })
  fechaDeseada?: string;

  @IsOptional()
  @IsIn(['am', 'pm'], { message: 'turnoDeseado debe ser am|pm' })
  turnoDeseado?: 'am' | 'pm';
}
