// src/controllers/equipos.reservas.controller.ts
import {
  Controller,
  Get,
  Post,
  Body,
  Query,
  BadRequestException,
  HttpCode,
} from '@nestjs/common';
import { DataSource } from 'typeorm';
import {
  ApiTags,
  ApiOperation,
  ApiBody,
  ApiQuery,
  ApiOkResponse,
  ApiCreatedResponse,
  ApiBadRequestResponse,
} from '@nestjs/swagger';
import { IsUUID, IsInt, Min } from 'class-validator';
import { Type } from 'class-transformer';

// ───────────────────────────────────────────────────────────────────────────────
// DTOs y modelos (Swagger)

class EquipoDto {
  id!: string;
  tipo!: string;
  sn!: string | null;
  mac!: string | null;
  estandar!: string | null;
  estado!: string;
  owner_tipo!: string | null;
  owner_id!: string | null;
  notas!: string | null;
  created_at!: string;
  updated_at!: string;
}

class ReservarDto {
  @ApiBody({ required: false })
  @IsUUID()
  id!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  tecnicoId!: number;
}

class LiberarDto {
  @IsUUID()
  id!: string;
}

class ReservarResponse {
  ok!: boolean;
  _idempotent!: boolean;
  equipo!: EquipoDto;
}

class LiberarResponse {
  ok!: boolean;
  _idempotent!: boolean;
  equipo!: EquipoDto;
}

// ───────────────────────────────────────────────────────────────────────────────

const RES_PREFIX = 'RESERVA:TEC-';

@ApiTags('Equipos / Reservas')
@Controller('equipos') // el prefijo global /v1 se aplica en bootstrap
export class EquiposReservasController {
  constructor(private readonly ds: DataSource) {}

  private async getEquipo(id: string): Promise<EquipoDto | null> {
    const rows = await this.ds.query(
      `select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at
         from equipos
        where id = $1::uuid`,
      [id],
    );
    return rows[0] ?? null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // POST /equipos/reservar
  @Post('reservar')
  @HttpCode(201)
  @ApiOperation({
    summary: 'Reservar un equipo para un técnico (idempotente por técnico)',
    description:
      'Marca el equipo en campo "notas" con RESERVA:TEC-{tecnicoId}. ' +
      'Si ya está reservado para ese técnico, responde como idempotente.',
  })
  @ApiBody({ type: ReservarDto })
  @ApiCreatedResponse({ type: ReservarResponse, description: 'Reserva creada o idempotente' })
  @ApiBadRequestResponse({ description: 'Validación o equipo no existe' })
  async reservar(@Body() dto: ReservarDto): Promise<ReservarResponse> {
    if (!dto?.id || !dto?.tecnicoId) {
      throw new BadRequestException('id y tecnicoId son obligatorios');
    }

    const equipo = await this.getEquipo(dto.id);
    if (!equipo) throw new BadRequestException('equipo no existe');

    const mark = `${RES_PREFIX}${dto.tecnicoId}`;
    const notas: string = equipo.notas ?? '';

    // Idempotencia: ya marcado para ese técnico
    if (notas.includes(mark)) {
      return { ok: true, _idempotent: true, equipo };
    }

    // Agrega marca de reserva preservando notas previas
    const newNotas = notas ? `${notas} | ${mark}` : mark;

    const up = await this.ds.query(
      `update equipos
          set notas = $2,
              updated_at = now()
        where id = $1::uuid
    returning id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at`,
      [dto.id, newNotas],
    );

    return { ok: true, _idempotent: false, equipo: up[0] as EquipoDto };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // POST /equipos/liberar
  @Post('liberar')
  @HttpCode(201)
  @ApiOperation({
    summary: 'Liberar cualquier reserva previa del equipo',
    description:
      'Quita TODAS las marcas RESERVA:TEC-* en "notas". ' +
      'Si no hay reservas, es idempotente.',
  })
  @ApiBody({ type: LiberarDto })
  @ApiCreatedResponse({ type: LiberarResponse, description: 'Equipo liberado o idempotente' })
  @ApiBadRequestResponse({ description: 'Validación o equipo no existe' })
  async liberar(@Body() dto: LiberarDto): Promise<LiberarResponse> {
    if (!dto?.id) throw new BadRequestException('id es obligatorio');

    const equipo = await this.getEquipo(dto.id);
    if (!equipo) throw new BadRequestException('equipo no existe');

    const notas: string = equipo.notas ?? '';
    const hadAny = notas.includes(RES_PREFIX);

    // Idempotente: no tenía reservas
    if (!hadAny) {
      return { ok: true, _idempotent: true, equipo };
    }

    // Quita cualquier marca RESERVA:TEC-*
    const newNotas = notas
      .split('|')
      .map((s) => s.trim())
      .filter((s) => s && !s.startsWith(RES_PREFIX))
      .join(' | ');

    const up = await this.ds.query(
      `update equipos
          set notas = $2,
              updated_at = now()
        where id = $1::uuid
    returning id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at`,
      [dto.id, newNotas || null],
    );

    return { ok: true, _idempotent: false, equipo: up[0] as EquipoDto };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // GET /equipos/reservas
  @Get('reservas')
  @ApiOperation({
    summary: 'Listar equipos reservados',
    description:
      'Si se pasa tecnicoId, filtra por RESERVA:TEC-{tecnicoId}. ' +
      'Si no, lista cualquier equipo que tenga alguna marca de reserva.',
  })
  @ApiQuery({
    name: 'tecnicoId',
    required: false,
    type: Number,
    description: 'Filtra por técnico (opcional)',
  })
  @ApiOkResponse({ type: [EquipoDto] })
  async reservas(@Query('tecnicoId') tecnicoId?: string): Promise<EquipoDto[]> {
    const mark = tecnicoId ? `${RES_PREFIX}${Number(tecnicoId)}` : RES_PREFIX;

    const rows = await this.ds.query(
      `select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at
         from equipos
        where notas is not null
          and notas like $1`,
      [`%${mark}%`],
    );

    return rows as EquipoDto[];
  }
}
