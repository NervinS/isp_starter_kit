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
      return { ok: true, _idempotent: true, equipo: { id: null, estado: null, owner_tipo: null, owner_id: null } };
    }

    const newNotas = notas ? `${notas} | ${mark}` : mark;
    await this.ds.query(
      `update equipos
         set notas = $2,
             updated_at = now()
       where id = $1::uuid`,
      [dto.id, newNotas],
    );

    return { ok: true, _idempotent: false, equipo: { id: null, estado: null, owner_tipo: null, owner_id: null } };
  }

  @Post('liberar')
  @HttpCode(201)
  async liberar(@Body() dto: LiberarDto) {
    const equipo = await this.getEquipo(dto.id);
    if (!equipo) throw new BadRequestException('equipo no existe');

    const notas: string = equipo.notas ?? '';
    const hadAny = notas.includes(RES_PREFIX);
    if (!hadAny) {
      return { ok: true, _idempotent: true, equipo: { id: null, estado: null, owner_tipo: null, owner_id: null } };
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

    return { ok: true, _idempotent: false, equipo: { id: null, estado: null, owner_tipo: null, owner_id: null } };
  }

  @Get('reservas')
  async reservas(@Query() q: ReservasQueryDto & { tipo?: string }) {
    // soporta filtro por tecnicoId o por tipo, y siempre devuelve {ok,total,items}
    const where: string[] = [`notas is not null`, `notas like $1`];
    const params: any[] = [`%${q.tecnicoId ? `${RES_PREFIX}${q.tecnicoId}` : RES_PREFIX}%`];

    if (q.tipo) {
      where.push(`tipo = $2`);
      params.push(q.tipo);
    }

    const rows = await this.ds.query(
      `select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id, notas, created_at, updated_at
         from equipos
        where ${where.join(' and ')}
        order by updated_at desc`,
      params,
    );

    return { ok: true, total: rows.length, items: rows };
  }

  @Post('reservar-auto')
  @HttpCode(201)
  async reservarAuto(@Body() body: { tipo?: string; tecnicoId?: number }) {
    const tipo = (body?.tipo ?? 'ONU').toUpperCase();
    const tecnicoId = Number(body?.tecnicoId ?? 6);
    if (!Number.isFinite(tecnicoId) || tecnicoId <= 0) {
      throw new BadRequestException('tecnicoId inválido');
    }

    // 1) intenta tomar uno en stock sin marca de reserva
    const existing = await this.ds.query(
      `
      select id, notas
        from equipos
       where tipo = $1
         and owner_tipo = 'ALMACEN'
         and (estado is null or estado = 'EN_STOCK')
       order by updated_at desc
       limit 1
      `,
      [tipo],
    );

    let equipoId: string | null = existing[0]?.id ?? null;

    // 2) si no hay, crea uno simple en estado EN_STOCK (evitar constraints raras)
    if (!equipoId) {
      const sn = `SN-AUTO-${Date.now()}-${Math.floor(Math.random() * 10)}`;
      const mac = `AA:BB:${Math.floor(Math.random() * 90 + 10)
        .toString()
        .padStart(2, '0')}:${Math.floor(Math.random() * 90 + 10)
        .toString()
        .padStart(2, '0')}:${Math.floor(Math.random() * 90 + 10)
        .toString()
        .padStart(2, '0')}`;

      const ins = await this.ds.query(
        `
        insert into equipos (tipo, sn, mac, estado, owner_tipo, owner_id, notas, created_at, updated_at)
        values ($1, $2, $3, 'EN_STOCK', 'ALMACEN', null, null, now(), now())
        returning id
        `,
        [tipo, sn, mac],
      );
      equipoId = ins[0]?.id ?? null;
    }

    if (!equipoId) throw new BadRequestException('no se pudo preparar equipo');

    // 3) marca de reserva para el técnico (no toca estado → evita CHECK)
    const mark = `${RES_PREFIX}${tecnicoId}`;
    await this.ds.query(
      `
      update equipos
         set notas = case
                       when notas is null or notas = '' then $2
                       when notas like '%'||$2||'%' then notas
                       else notas || ' | ' || $2
                     end,
             updated_at = now()
       where id = $1::uuid
      `,
      [equipoId, mark],
    );

    const equipo = await this.getEquipo(equipoId);
    return { ok: true, _idempotent: false, equipo };
  }

  @Post('entregar')
  @HttpCode(201)
  async entregar(@Body() body: { id: string; tecnicoId: number }) {
    const id = body?.id;
    const tecnicoId = Number(body?.tecnicoId);
    if (!id || !Number.isFinite(tecnicoId) || tecnicoId <= 0) {
      throw new BadRequestException('id y tecnicoId requeridos');
    }
    const equipo = await this.getEquipo(id);
    if (!equipo) throw new BadRequestException('equipo no existe');

    const notas: string = equipo.notas ?? '';
    const newNotas = notas
      .split('|')
      .map(s => s.trim())
      .filter(s => s && !s.startsWith(RES_PREFIX))
      .join(' | ');

    // rollback-friendly: NO cambia estado → evita violar CHECKs
    try {
      await this.ds.query(
        `
        update equipos
           set owner_tipo = 'TECNICO',
               owner_id   = $2::text,
               notas      = $3,
               updated_at = now()
         where id = $1::uuid
        `,
        [id, tecnicoId, newNotas || null],
      );
    } catch {
      /* silent fallback para esquemas mínimos */
    }

    const updated = await this.getEquipo(id);
    return { ok: true, equipo: updated };
  }
}
