// src/modules/ordenes/dto/create-orden.dto.ts
import { IsUUID, IsIn, IsOptional } from 'class-validator';

export type TipoOrden =
  | 'MAN'  // mantenimiento (técnica)
  | 'COR'  // corte (admin, auto-cierre -> usuario.desconectado)
  | 'REC'  // reconexión (admin, auto-cierre -> usuario.instalado)
  | 'BAJ'  // baja total (admin, auto-cierre -> usuario.terminado)
  | 'TRA'  // traslado (técnica)
  | 'CMB'  // cambio de equipo (técnica)
  | 'RCT'; // recontratación (técnica)

export class CreateOrdenDto {
  @IsUUID()
  usuarioId!: string;

  @IsIn(['MAN','COR','REC','BAJ','TRA','CMB','RCT'])
  tipo!: TipoOrden;

  @IsOptional()
  tecnicoId?: string | null;
}
