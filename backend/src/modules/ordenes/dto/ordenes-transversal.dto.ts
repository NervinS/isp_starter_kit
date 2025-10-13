// src/modules/ordenes/dto/ordenes-transversal.dto.ts
import { IsArray, IsEnum, IsNotEmpty, IsNumber, IsOptional, IsString, IsUUID, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export type OrdenTipo = 'INS' | 'COR' | 'REC' | 'BAJ' | 'TRA' | 'CMB' | 'RCT';

export class MaterialLineaDto {
  @IsNumber() materialId!: number;
  @IsString() codigo!: string;
  @IsString() nombre!: string;
  @IsNumber() cantidad!: number;
  @IsNumber() @IsOptional() precio?: number;
}

export class EquiposAccionDto {
  @IsEnum(['asignar','retirar'] as const) @IsString() accion!: 'asignar' | 'retirar';
  @IsEnum(['ONU','ONT','REPETIDOR','ROUTER'] as const) @IsString() tipo!: 'ONU'|'ONT'|'REPETIDOR'|'ROUTER';
  @IsString() sn!: string;
  @IsString() @IsOptional() mac?: string;
  @IsString() @IsOptional() estandar?: string;
}

export class EvidenciasUpsertDto {
  // modo presigned: llaves ya subidas a MinIO/S3 (recomendado en móvil)
  @IsString() @IsOptional() foto1_key?: string;
  @IsString() @IsOptional() foto2_key?: string;
  @IsString() @IsOptional() foto3_key?: string;
  @IsString() @IsOptional() firma_key?: string;

  // modo inline: base64 (opcional; si llegan se suben a MinIO)
  @IsString() @IsOptional() foto1_base64?: string;
  @IsString() @IsOptional() foto2_base64?: string;
  @IsString() @IsOptional() foto3_base64?: string;
  @IsString() @IsOptional() firma_base64?: string;
}

export class CerrarOrdenDto {
  @IsEnum(['INS','COR','REC','BAJ','TRA','CMB','RCT'] as const) @IsString()
  tipo!: OrdenTipo;

  // material/equipos “ejecutados” opcionales (si el cierre los incluye)
  @IsArray() @ValidateNested({ each: true }) @Type(() => MaterialLineaDto) @IsOptional()
  materiales?: MaterialLineaDto[];

  @IsArray() @ValidateNested({ each: true }) @Type(() => EquiposAccionDto) @IsOptional()
  equipos?: EquiposAccionDto[];

  // payload crudo para auditoría (forma libre del cliente/app)
  // lo guardará la estrategia/servicio real
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  payloadCierre?: any;
}

export class OrdenEquiposAccionesDto {
  @IsArray() @ValidateNested({ each: true }) @Type(() => EquiposAccionDto)
  acciones!: EquiposAccionDto[];
}

// ---------- Respuesta GET /ordenes/:codigo ----------
export interface OrdenGetResponse {
  codigo: string;
  tipo: OrdenTipo;
  estado: string;
  turno?: string | null;
  agendadoPara?: string | null; // ISO
  tecnico?: { id: string | number; nombre?: string } | null;
  createdAt?: string;
  updatedAt?: string;

  materiales: {
    planificados: MaterialLineaDto[];
    ejecutados:   MaterialLineaDto[];
  };

  equipos: {
    asignar: EquiposAccionDto[];
    retirar: EquiposAccionDto[];
  };

  evidencias: {
    foto1Key?: string;
    foto2Key?: string;
    foto3Key?: string;
    firmaKey?: string;
  };

  pdf: {
    pdfKey?: string | null;
    pdfUrl?: string | null;
  };

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  payloadCierre?: any; // raw para auditoría (si existe)
}
