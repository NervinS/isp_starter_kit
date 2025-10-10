// src/controllers/equipos.controller.ts
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  NotFoundException,
  Post,
  Query,
} from '@nestjs/common';
import { DataSource } from 'typeorm';
import { ApiOperation, ApiQuery, ApiResponse, ApiTags, ApiBody } from '@nestjs/swagger';

type EquipoRow = {
  id: string;
  tipo: 'ONU' | 'REPETIDOR';
  sn: string;
  mac: string;
  estandar: string | null;
  estado: string; // 'EN_STOCK'
  owner_tipo: 'ALMACEN' | 'TECNICO';
  owner_id: string; // 'ALM-PRINC' | 'TEC-6' etc
};

function normalizeTipo(tipo?: string) {
  if (!tipo) throw new BadRequestException('tipo requerido');
  const t = tipo.toUpperCase() === 'ONT' ? 'ONU' : tipo.toUpperCase();
  if (!['ONU', 'REPETIDOR'].includes(t)) {
    throw new BadRequestException('tipo debe ser ONU|REPETIDOR|ONT');
  }
  return t as 'ONU' | 'REPETIDOR';
}

@ApiTags('Equipos')
@Controller('equipos') // el /v1 lo agrega el globalPrefix en main.ts
export class EquiposController {
  constructor(private readonly dataSource: DataSource) {}

  // ---------------------------------------------------------------------------
  // 1) Disponibles (ya existente)
  // ---------------------------------------------------------------------------
  @Get('disponibles')
  @ApiOperation({ summary: 'Listar equipos disponibles por tipo' })
  @ApiQuery({ name: 'tipo', enum: ['ONU', 'REPETIDOR', 'ONT'], required: true })
  @ApiQuery({ name: 'tecnico', required: false, description: 'Reservado; hoy se ignora' })
  @ApiResponse({ status: 200, description: 'OK' })
  @ApiResponse({ status: 400, description: 'Parámetros inválidos' })
  async disponibles(@Query('tipo') tipo?: string) {
    const norm = normalizeTipo(tipo);
    const rows = await this.dataSource.query<EquipoRow[]>(
      `
      select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id
      from equipos
      where estado = 'EN_STOCK'
        and owner_tipo = 'ALMACEN'
        and tipo = $1
      order by created_at desc
      `,
      [norm],
    );
    return rows;
  }

  // ---------------------------------------------------------------------------
  // 2) Entregar (ALMACEN -> TECNICO), idempotente
  // body: { id: string, tecnicoId: number, fromAlmacen?: string }
  // ---------------------------------------------------------------------------
  @Post('entregar')
  @ApiOperation({ summary: 'Entregar equipo a técnico (ALMACEN -> TECNICO), idempotente' })
  @ApiBody({
    schema: {
      type: 'object',
      required: ['id', 'tecnicoId'],
      properties: {
        id: { type: 'string', format: 'uuid' },
        tecnicoId: { type: 'integer' },
        fromAlmacen: { type: 'string', example: 'ALM-PRINC' },
      },
    },
  })
  async entregar(
    @Body('id') id: string,
    @Body('tecnicoId') tecnicoId?: number,
    @Body('fromAlmacen') fromAlmacen = 'ALM-PRINC',
  ) {
    if (!id) throw new BadRequestException('id requerido');
    if (!tecnicoId || Number.isNaN(+tecnicoId)) {
      throw new BadRequestException('tecnicoId requerido');
    }
    const tecCode = `TEC-${tecnicoId}`;

    const rows = await this.dataSource.query<EquipoRow[]>(
      `select * from equipos where id=$1`,
      [id],
    );
    if (rows.length === 0) throw new NotFoundException('equipo no encontrado');
    const eq = rows[0];

    // Idempotencia: ya en el técnico correcto -> no-op
    if (eq.owner_tipo === 'TECNICO' && eq.owner_id === tecCode) {
      return { ok: true, from: null, to: [], _idempotent: true };
    }

    // Validación conservadora para no desajustar saldos
    if (!(eq.owner_tipo === 'ALMACEN' && eq.owner_id === fromAlmacen)) {
      throw new BadRequestException(
        `estado actual incompatible: owner=${eq.owner_tipo}/${eq.owner_id}, esperado ALMACEN/${fromAlmacen}`,
      );
    }

    // Transferencia
    await this.dataSource.query(
      `update equipos set owner_tipo='TECNICO', owner_id=$2 where id=$1`,
      [id, tecCode],
    );

    const updated = await this.dataSource.query<EquipoRow[]>(
      `select * from equipos where id=$1`,
      [id],
    );

    return { ok: true, from: eq, to: updated, _idempotent: false };
  }

  // ---------------------------------------------------------------------------
  // 3) Devolver (TECNICO -> ALMACEN), idempotente  [NUEVO – Fase 4]
  // body: { id: string, tecnicoId?: number, toAlmacen?: string }
  //  - tecnicoId opcional: si se omite, se tolera idempotencia si YA está en ALMACEN/toAlmacen
  // ---------------------------------------------------------------------------
  @Post('devolver')
  @ApiOperation({ summary: 'Devolver equipo a almacén (TECNICO -> ALMACEN), idempotente' })
  @ApiBody({
    schema: {
      type: 'object',
      required: ['id'],
      properties: {
        id: { type: 'string', format: 'uuid' },
        tecnicoId: { type: 'integer', nullable: true },
        toAlmacen: { type: 'string', example: 'ALM-PRINC' },
      },
    },
  })
  async devolver(
    @Body('id') id: string,
    @Body('tecnicoId') tecnicoId?: number,
    @Body('toAlmacen') toAlmacen = 'ALM-PRINC',
  ) {
    if (!id) throw new BadRequestException('id requerido');

    const rows = await this.dataSource.query<EquipoRow[]>(
      `select * from equipos where id=$1`,
      [id],
    );
    if (rows.length === 0) throw new NotFoundException('equipo no encontrado');
    const eq = rows[0];

    // Idempotencia: ya en el almacén destino
    if (eq.owner_tipo === 'ALMACEN' && eq.owner_id === toAlmacen) {
      return { ok: true, from: null, to: [], _idempotent: true };
    }

    // Si llega tecnicoId, validamos que efectivamente esté en ese técnico
    if (typeof tecnicoId === 'number') {
      const tecCode = `TEC-${tecnicoId}`;
      if (!(eq.owner_tipo === 'TECNICO' && eq.owner_id === tecCode)) {
        throw new BadRequestException(
          `estado actual incompatible: owner=${eq.owner_tipo}/${eq.owner_id}, esperado TECNICO/${tecCode}`,
        );
      }
    } else {
      // Sin tecnicoId: aceptamos devolver solo si realmente está en algún técnico
      if (eq.owner_tipo !== 'TECNICO') {
        throw new BadRequestException(
          `estado actual incompatible: owner=${eq.owner_tipo}/${eq.owner_id}, esperado TECNICO`,
        );
      }
    }

    await this.dataSource.query(
      `update equipos set owner_tipo='ALMACEN', owner_id=$2 where id=$1`,
      [id, toAlmacen],
    );

    const updated = await this.dataSource.query<EquipoRow[]>(
      `select * from equipos where id=$1`,
      [id],
    );

    return { ok: true, from: eq, to: updated, _idempotent: false };
  }

  // ---------------------------------------------------------------------------
  // 4) Stock (lectura)  [NUEVO – Fase 5]
  // GET /v1/equipos/stock?almacen=ALM-PRINC
  // GET /v1/equipos/stock?tecnicoId=6
  // ---------------------------------------------------------------------------
  @Get('stock')
  @ApiOperation({ summary: 'Listar stock de equipos (por almacén o por técnico)' })
  @ApiQuery({ name: 'almacen', required: false, description: 'Código de almacén (p.ej. ALM-PRINC)' })
  @ApiQuery({ name: 'tecnicoId', required: false, description: 'Id de técnico (numérico)' })
  async stock(@Query('almacen') almacen?: string, @Query('tecnicoId') tecnicoId?: string) {
    if (!almacen && !tecnicoId) {
      throw new BadRequestException('debe especificar almacen o tecnicoId');
    }
    if (almacen && tecnicoId) {
      throw new BadRequestException('use solo uno: almacen o tecnicoId');
    }

    if (almacen) {
      const rows = await this.dataSource.query<EquipoRow[]>(
        `
        select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id
        from equipos
        where estado='EN_STOCK'
          and owner_tipo='ALMACEN'
          and owner_id=$1
        order by created_at desc
        `,
        [almacen],
      );
      return rows;
    }

    // tecnicoId
    const tecIdNum = parseInt(String(tecnicoId ?? ''), 10);
    if (Number.isNaN(tecIdNum)) throw new BadRequestException('tecnicoId inválido');
    const tecCode = `TEC-${tecIdNum}`;

    const rows = await this.dataSource.query<EquipoRow[]>(
      `
      select id, tipo, sn, mac, estandar, estado, owner_tipo, owner_id
      from equipos
      where estado='EN_STOCK'
        and owner_tipo='TECNICO'
        and owner_id=$1
      order by created_at desc
      `,
      [tecCode],
    );
    return rows;
  }
}
