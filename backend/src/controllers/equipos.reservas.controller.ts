// src/controllers/equipos.reservas.controller.ts
import { Controller, Get, Post, Body, Query, BadRequestException, HttpCode } from '@nestjs/common';
import { DataSource } from 'typeorm';
import {
  ApiTags,
  ApiOperation,
  ApiBody,
  ApiOkResponse,
  ApiCreatedResponse,
  ApiQuery,
} from '@nestjs/swagger';
import { ReservarDto, LiberarDto } from './equipos.reservas.dto';

const RES_PREFIX = 'RESERVA:TEC-';

@ApiTags('Equipos / Reservas')
@Controller('equipos')
export class EquiposReservasController {
  constructor(private readonly ds: DataSource) {}

  private async getEquipo(id: string) {
    const rows = await this.ds.query(
      `select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at
       from equipos where id = $1::uuid`,
      [id],
    );
    return rows[0] ?? null;
  }

  // ----------------------------------------
  // POST /v1/equipos/reservar
  // ----------------------------------------
  @Post('reservar')
  @HttpCode(201)
  @ApiOperation({ summary: 'Reservar equipo para un técnico (idempotente por técnico)' })
  @ApiBody({ type: ReservarDto })
  @ApiCreatedResponse({
    description: 'Reserva creada o idempotente',
    schema: {
      example: {
        ok: true,
        _idempotent: false,
        equipo: {
          id: '69ddc2d8-cae7-46f1-a670-e2e304ae0e98',
          tipo: 'ONU',
          sn: 'ONT-DEMO-002',
          mac: 'AA:BB:CC:DD:EE:02',
          estandar: 'wifi6',
          estado: 'EN_STOCK',
          owner_tipo: 'ALMACEN',
          owner_id: 'ALM-PRINC',
          notas: 'seed | RESERVA:TEC-6',
          created_at: '2025-10-10T14:21:28.103Z',
          updated_at: '2025-10-10T18:55:55.504Z',
        },
      },
    },
  })
  async reservar(@Body() dto: ReservarDto) {
    if (!dto?.id || !dto?.tecnicoId) throw new BadRequestException('id y tecnicoId son obligatorios');
    const equipo = await this.getEquipo(dto.id);
    if (!equipo) throw new BadRequestException('equipo no existe');

    const mark = `${RES_PREFIX}${dto.tecnicoId}`;
    const notas: string = equipo.notas ?? '';

    // idempotencia: ya marcado para este técnico
    if (notas.includes(mark)) {
      return { ok: true, _idempotent: true, equipo };
    }

    // agrega marca de reserva preservando notas previas
    const newNotas = notas ? `${notas} | ${mark}` : mark;
    const up = await this.ds.query(
      `update equipos
         set notas = $2,
             updated_at = now()
       where id = $1::uuid
       returning id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at`,
      [dto.id, newNotas],
    );

    const updated = Array.isArray(up) ? up[0] : up;
    return { ok: true, _idempotent: false, equipo: updated };
  }

  // ----------------------------------------
  // POST /v1/equipos/liberar
  // ----------------------------------------
  @Post('liberar')
  @HttpCode(201)
  @ApiOperation({ summary: 'Liberar todas las marcas RESERVA:TEC-* del equipo (idempotente)' })
  @ApiBody({ type: LiberarDto })
  @ApiCreatedResponse({
    description: 'Liberación aplicada o idempotente',
    schema: {
      example: {
        ok: true,
        _idempotent: false,
        equipo: {
          id: '69ddc2d8-cae7-46f1-a670-e2e304ae0e98',
          tipo: 'ONU',
          sn: 'ONT-DEMO-002',
          mac: 'AA:BB:CC:DD:EE:02',
          estandar: 'wifi6',
          estado: 'EN_STOCK',
          owner_tipo: 'ALMACEN',
          owner_id: 'ALM-PRINC',
          notas: 'seed',
          created_at: '2025-10-10T14:21:28.103Z',
          updated_at: '2025-10-10T19:04:41.291Z',
        },
      },
    },
  })
  async liberar(@Body() dto: LiberarDto) {
    if (!dto?.id) throw new BadRequestException('id es obligatorio');
    const equipo = await this.getEquipo(dto.id);
    if (!equipo) throw new BadRequestException('equipo no existe');

    const notas: string = equipo.notas ?? '';
    const hadAny = notas.includes(RES_PREFIX);
    if (!hadAny) {
      return { ok: true, _idempotent: true, equipo };
    }

    // quita cualquier marca RESERVA:TEC-*
    const newNotas = notas
      .split('|')
      .map(s => s.trim())
      .filter(s => s && !s.startsWith(RES_PREFIX))
      .join(' | ');

    const up = await this.ds.query(
      `update equipos
         set notas = $2,
             updated_at = now()
       where id = $1::uuid
       returning id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at`,
      [dto.id, newNotas || null],
    );

    const updated = Array.isArray(up) ? up[0] : up;
    return { ok: true, _idempotent: false, equipo: updated };
  }

  // ----------------------------------------
  // GET /v1/equipos/reservas?tecnicoId=6
  // ----------------------------------------
  @Get('reservas')
  @ApiOperation({ summary: 'Listar equipos con marca de reserva' })
  @ApiQuery({ name: 'tecnicoId', required: false, type: Number, description: 'Si se omite, trae todas las reservas' })
  @ApiOkResponse({
    description: 'Listado de equipos reservados',
    schema: {
      example: [
        {
          id: '69ddc2d8-cae7-46f1-a670-e2e304ae0e98',
          tipo: 'ONU',
          sn: 'ONT-DEMO-002',
          mac: 'AA:BB:CC:DD:EE:02',
          estandar: 'wifi6',
          estado: 'EN_STOCK',
          owner_tipo: 'ALMACEN',
          owner_id: 'ALM-PRINC',
          notas: 'seed | RESERVA:TEC-6',
          created_at: '2025-10-10T14:21:28.103Z',
          updated_at: '2025-10-10T18:55:55.504Z',
        },
      ],
    },
  })
  async reservas(@Query('tecnicoId') tecnicoId?: string) {
    const mark = tecnicoId ? `${RES_PREFIX}${Number(tecnicoId)}` : RES_PREFIX;
    const rows = await this.ds.query(
      `select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at
         from equipos
        where notas is not null
          and notas like $1`,
      [`%${mark}%`],
    );
    return rows;
  }
}
