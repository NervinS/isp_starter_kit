// dto/ordenes.dto.ts
export class CrearOrdenDto {
  tipo: 'MAN'|'COR'|'REC'|'BAJ'|'TRA'|'CMB'|'RCT';
  tecnicoId?: string;
  usuarioId: string; // o cliente_codigo
  payload_abierto?: Record<string, any>;
}

export class GuardarOrdenDto {
  payload_abierto: Record<string, any>;
}

export class CerrarOrdenDto {
  payload_cierre: Record<string, any>;
  materiales?: Array<{ materialId: number; cantidad: number }>;
  equipos?: Array<{ equipo_tipo: 'ONT'|'REPEATER'; serial: string; accion: 'asignar'|'retirar'|'mantener' }>;
}

export class EvidenciasOrdenDto {
  // se maneja vía @UseInterceptors(FilesInterceptor(...)); validar mimetypes
}
