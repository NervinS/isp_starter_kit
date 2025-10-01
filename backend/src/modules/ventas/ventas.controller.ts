// src/modules/ventas/ventas.controller.ts
import {
  BadRequestException,
  Controller,
  Post,
  Param,
  Body,
  Get,
  Query,
  Headers,
} from '@nestjs/common';
import { DataSource } from 'typeorm';

type EvidenciasBody = {
  cedula_key?: string | null;
  recibo_key?: string | null;
  firma_key?: string | null;
};

@Controller('ventas') // /v1/ventas por GlobalPrefix('/v1')
export class VentasController {
  constructor(private readonly ds: DataSource) {}

  @Post()
  async crear(@Body() body: any) {
    const req = (k: string) => {
      if (!body?.[k]) throw new BadRequestException(`campo requerido: ${k}`);
      return body[k];
    };
    const cliente_nombre = req('cliente_nombre');
    const cliente_apellido = req('cliente_apellido');
    const documento = req('documento');
    const plan = req('plan');
    const total = Number(req('total'));
    if (Number.isNaN(total)) throw new BadRequestException('total inválido');

    const { ym } = (await this.ds.query(`SELECT to_char(now(),'YYYYMM') AS ym`))[0];
    const seqRow = await this.ds.query(
      `
      SELECT LPAD(COALESCE(MAX(SUBSTR(codigo, 10)::int) + 1, 1)::text, 4, '0') AS seq
      FROM ventas
      WHERE SUBSTR(codigo, 1, 8) = 'VTA-${ym}-'
      `,
    );
    const seq = seqRow?.[0]?.seq ?? '0001';
    const codigo = `VTA-${ym}-${seq}`;

    const q = `
      INSERT INTO ventas (codigo, cliente_nombre, cliente_apellido, documento, usuario_id, estado, plan, mensual_total, total, created_at)
      VALUES ($1,$2,$3,$4, gen_random_uuid(), 'creada', $5, $6, $7, now())
      ON CONFLICT (codigo) DO NOTHING
      RETURNING id, codigo, estado
    `;
    const r = await this.ds.query(q, [codigo, cliente_nombre, cliente_apellido, documento, plan, total, total]);
    if (!r.length) {
      const exist = await this.ds.query(`SELECT id, codigo, estado FROM ventas WHERE codigo=$1`, [codigo]);
      return exist[0];
    }
    return r[0];
  }

  @Get()
  async listar(@Query('estado') estado?: string) {
    if (estado) {
      return this.ds.query(`SELECT * FROM ventas WHERE estado = $1 ORDER BY created_at DESC LIMIT 200`, [estado]);
    }
    return this.ds.query(`SELECT * FROM ventas ORDER BY created_at DESC LIMIT 200`);
  }

  /** Detalle de venta + evidencias + INS no anulada (si existe) */
  @Get(':codigo')
  async detalle(@Param('codigo') codigo: string) {
    const venta = (
      await this.ds.query(
        `SELECT v.*
           FROM ventas v
          WHERE v.codigo = $1
          LIMIT 1`,
        [codigo],
      )
    )[0];
    if (!venta) throw new BadRequestException('Venta no existe');

    const orden =
      (
        await this.ds.query(
          `SELECT id,
                  codigo,
                  estado,
                  tipo,
                  agendado_para AS "agendadoPara",
                  tecnico_id    AS "tecnicoId"
             FROM ordenes
            WHERE venta_id = $1
              AND tipo = 'INS'
              AND estado <> 'anulada'
            LIMIT 1`,
          [venta.id],
        )
      )[0] ?? null;

    return {
      venta: {
        codigo: venta.codigo,
        estado: venta.estado,
        cliente_nombre: venta.cliente_nombre,
        cliente_apellido: venta.cliente_apellido,
        documento: venta.documento,
        plan: venta.plan,
        mensual_total: venta.mensual_total,
        total: venta.total,
        recibo_pdf_key: venta.recibo_pdf_key ?? null,
        contrato_pdf_key: venta.contrato_pdf_key ?? null,
        evidencias: {
          cedula_img_key: venta.cedula_img_key ?? null,
          recibo_img_key: venta.recibo_img_key ?? null,
          firma_img_key: venta.firma_img_key ?? null,
        },
        created_at: venta.created_at,
      },
      orden,
    };
  }

  @Post(':codigo/evidencias')
  async evidencias(@Param('codigo') codigo: string, @Body() body: EvidenciasBody) {
    const { cedula_key = null, recibo_key = null, firma_key = null } = body ?? {};

    return this.ds.transaction(async (trx) => {
      const ventaRows = await trx.query(`SELECT * FROM ventas WHERE codigo = $1 FOR UPDATE`, [codigo]);
      if (ventaRows.length === 0) throw new BadRequestException('Venta no existe');
      const venta = ventaRows[0];

      await trx.query(
        `UPDATE ventas
           SET cedula_img_key = COALESCE($2, cedula_img_key),
               recibo_img_key = COALESCE($3, recibo_img_key),
               firma_img_key  = COALESCE($4, firma_img_key)
         WHERE id = $1`,
        [venta.id, cedula_key, recibo_key, firma_key],
      );

      const out = await trx.query(
        `SELECT codigo, estado, cedula_img_key, recibo_img_key, firma_img_key
           FROM ventas WHERE id=$1`,
        [venta.id],
      );
      return out[0];
    });
  }

  /** Asegura que exista una INS no anulada para la venta; si no, la crea (pendiente). */
  @Post(':codigo/asegurar-ins')
  async asegurarIns(@Param('codigo') codigo: string) {
    return this.ds.transaction(async (trx) => {
      const ventaRows = await trx.query(`SELECT * FROM ventas WHERE codigo=$1 FOR UPDATE`, [codigo]);
      if (!ventaRows.length) throw new BadRequestException('Venta no existe');
      const venta = ventaRows[0];

      if (venta.estado !== 'pagada') {
        throw new BadRequestException('La venta debe estar pagada para generar INS');
      }

      // Busca INS activa (no anulada)
      let orden =
        (
          await trx.query(
            `SELECT id, codigo, estado, tipo, agendado_para AS "agendadoPara", tecnico_id AS "tecnicoId"
               FROM ordenes
              WHERE venta_id = $1 AND tipo='INS' AND estado <> 'anulada'
              LIMIT 1`,
            [venta.id],
          )
        )[0] ?? null;

      // Si no hay, genera nueva
      if (!orden) {
        const nextNumRow = await trx.query(
          `SELECT LPAD(COALESCE(MAX(CASE WHEN codigo LIKE 'INS-%' THEN SUBSTR(codigo,5)::int END) + 1, 1)::text, 6, '0') AS seq
             FROM ordenes`,
        );
        const seq = nextNumRow?.[0]?.seq ?? '000001';
        const ordCodigo = `INS-${seq}`;

        const insertOrd = await trx.query(
          `INSERT INTO ordenes (codigo, tipo, estado, venta_id)
             VALUES ($1,'INS','pendiente',$2)
             RETURNING id, codigo, estado, tipo, agendado_para AS "agendadoPara", tecnico_id AS "tecnicoId"`,
          [ordCodigo, venta.id],
        );
        orden = insertOrd[0];
      }

      return orden;
    });
  }

  @Post(':codigo/pagar')
  async pagar(@Param('codigo') codigo: string, @Headers('idempotency-key') idemKey?: string) {
    if (!idemKey) throw new BadRequestException('Idempotency-Key requerido');

    return this.ds.transaction(async (trx) => {
      // 0) Lock venta
      const ventaRows = await trx.query(`SELECT * FROM ventas WHERE codigo = $1 FOR UPDATE`, [codigo]);
      if (ventaRows.length === 0) throw new BadRequestException('Venta no existe');
      const venta = ventaRows[0];

      // 1) Registrar Idempotency-Key sin abortar TX
      const ins = await trx.query(
        `INSERT INTO venta_pagos_idem (idem_key, venta_id)
         VALUES ($1, $2)
         ON CONFLICT (idem_key) DO NOTHING
         RETURNING id`,
        [idemKey, venta.id],
      );
      if (!ins.length) {
        const ord = await trx.query(
          `SELECT id, codigo, estado, tipo, agendado_para AS "agendadoPara"
             FROM ordenes
            WHERE venta_id = $1 AND tipo = 'INS' AND estado <> 'anulada'
            LIMIT 1`,
          [venta.id],
        );
        return {
          _idempotent: true,
          venta: {
            codigo: venta.codigo,
            estado: venta.estado,
            recibo_pdf_key: venta.recibo_pdf_key ?? null,
            contrato_pdf_key: venta.contrato_pdf_key ?? null,
          },
          orden: ord[0] ?? null,
        };
      }

      // 2) Reglas de negocio mínimas
      if (!venta.firma_img_key) {
        throw new BadRequestException('Falta firma: carga firma antes de pagar (/ventas/:codigo/evidencias)');
      }

      // 3) Si ya está pagada -> idempotente
      if (venta.estado === 'pagada') {
        const ord = await trx.query(
          `SELECT id, codigo, estado, tipo, agendado_para AS "agendadoPara"
             FROM ordenes
            WHERE venta_id = $1 AND tipo = 'INS' AND estado <> 'anulada'
            LIMIT 1`,
          [venta.id],
        );
        return {
          _idempotent: true,
          venta: {
            codigo: venta.codigo,
            estado: venta.estado,
            recibo_pdf_key: venta.recibo_pdf_key ?? null,
            contrato_pdf_key: venta.contrato_pdf_key ?? null,
          },
          orden: ord[0] ?? null,
        };
      }

      // TODO: validar cobertura cuando integremos catálogo/dirección
      // TODO: generar PDFs reales y guardar *_pdf_key
      const recibo_pdf_key = venta.recibo_pdf_key ?? null;
      const contrato_pdf_key = venta.contrato_pdf_key ?? null;

      await trx.query(
        `UPDATE ventas SET estado='pagada', recibo_pdf_key=$2, contrato_pdf_key=$3 WHERE id=$1`,
        [venta.id, recibo_pdf_key, contrato_pdf_key],
      );

      // 4) INS única (no anulada)
      let orden =
        (
          await trx.query(
            `SELECT id, codigo, estado, tipo, agendado_para AS "agendadoPara"
               FROM ordenes
              WHERE venta_id = $1 AND tipo = 'INS' AND estado <> 'anulada'
              LIMIT 1`,
            [venta.id],
          )
        )[0] ?? null;

      if (!orden) {
        const nextNumRow = await trx.query(
          `SELECT LPAD(COALESCE(MAX(CASE WHEN codigo LIKE 'INS-%' THEN SUBSTR(codigo,5)::int END) + 1, 1)::text, 6, '0') AS seq
             FROM ordenes`,
        );
        const seq = nextNumRow?.[0]?.seq ?? '000001';
        const ordCodigo = `INS-${seq}`;

        const insertOrd = await trx.query(
          `INSERT INTO ordenes (codigo, tipo, estado, venta_id)
             VALUES ($1,'INS','pendiente',$2)
             RETURNING id, codigo, estado, tipo, agendado_para AS "agendadoPara"`,
          [ordCodigo, venta.id],
        );
        orden = insertOrd[0];
      }

      return {
        _idempotent: false,
        venta: {
          codigo: venta.codigo,
          estado: 'pagada',
          recibo_pdf_key,
          contrato_pdf_key,
        },
        orden,
      };
    });
  }
}
