// src/controllers/equipos.reservas.controller.ts
import { Controller, Get, Post, Body, Query, BadRequestException, HttpCode } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { ReservarDto, LiberarDto, ReservasQueryDto } from './equipos.reservas.dto';

const RES_PREFIX = 'RESERVA:TEC-';

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

  @Post('reservar')
  @HttpCode(201)
  async reservar(@Body() dto: ReservarDto) {
    const equipo = await this.getEquipo(dto.id);
    if (!equipo) throw new BadRequestException('equipo no existe');

    const mark = `${RES_PREFIX}${dto.tecnicoId}`;
    const notas: string = equipo.notas ?? '';

    if (notas.includes(mark)) {
      return { ok: true, _idempotent: true, equipo };
    }

    const newNotas = notas ? `${notas} | ${mark}` : mark;
    await this.ds.query(
      `update equipos
         set notas = $2,
             updated_at = now()
       where id = $1::uuid`,
      [dto.id, newNotas],
    );

    // Post-SELECT para contrato estable (equipo SIEMPRE objeto)
    const updated = await this.getEquipo(dto.id);
    return { ok: true, _idempotent: false, equipo: updated };
  }

  @Post('liberar')
  @HttpCode(201)
  async liberar(@Body() dto: LiberarDto) {
    const equipo = await this.getEquipo(dto.id);
    if (!equipo) throw new BadRequestException('equipo no existe');

    const notas: string = equipo.notas ?? '';
    const hadAny = notas.includes(RES_PREFIX);
    if (!hadAny) {
      return { ok: true, _idempotent: true, equipo };
    }

    const newNotas = notas
      .split('|')
      .map(s => s.trim())
      .filter(s => s && !s.startsWith(RES_PREFIX))
      .join(' | ');

    await this.ds.query(
      `update equipos
         set notas = $2,
             updated_at = now()
       where id = $1::uuid`,
      [dto.id, newNotas || null],
    );

    const updated = await this.getEquipo(dto.id);
    return { ok: true, _idempotent: false, equipo: updated };
  }

  @Get('reservas')
  async reservas(@Query() q: ReservasQueryDto) {
    const mark = q.tecnicoId ? `${RES_PREFIX}${q.tecnicoId}` : RES_PREFIX;
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
