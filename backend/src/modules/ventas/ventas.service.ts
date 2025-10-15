// src/modules/ventas/ventas.service.ts
import {
  Injectable,
  BadRequestException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { DataSource } from 'typeorm';

// === Tipos ligeros ===
type VentaEstado = 'creada' | 'pagada' | 'anulada';

interface CrearVentaDto {
  cliente_nombre: string;
  cliente_apellido: string;
  documento: string;
  plan: string;          // Ej: "FTTH 100M"
  total: number | string;
  mensual_total?: number | string | null; // opcional (ej. suma de recurrentes)
}

interface EvidenciasDto {
  firma_key?: string | null;
  cedula_key?: string | null;
  recibo_key?: string | null;

  firma_base64?: string | null;
  cedula_base64?: string | null;
  recibo_base64?: string | null;
}

@Injectable()
export class VentasService {
  private readonly log = new Logger('VentasService');

  constructor(private readonly ds: DataSource) {}

  // ===========================================================================
  // Helpers
  // ===========================================================================

  private async nextCodigoVenta(): Promise<string> {
    // Formato: VTA-YYYYMM-#### (secuencia por mes)
    const { ym } = (await this.ds.query(`SELECT to_char(now(),'YYYYMM') AS ym`))[0];
    const seqRow = await this.ds.query(
      `
      SELECT LPAD(
               COALESCE(MAX(SUBSTR(codigo, 10)::int) + 1, 1)::text,
               4, '0'
             ) AS seq
        FROM ventas
       WHERE SUBSTR(codigo, 1, 8) = $1
      `,
      [`VTA-${ym}-`],
    );
    const seq: string = seqRow?.[0]?.seq ?? '0001';
    return `VTA-${ym}-${seq}`;
  }

  private numOrNull(v: unknown): number | null {
    if (v === null || v === undefined || v === '') return null;
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }

  private async getVentaByCodigo(codigo: string) {
    const rows = await this.ds.query(
      `
      SELECT id, codigo, estado,
             cliente_nombre, cliente_apellido, documento,
             plan, mensual_total, total,
             cedula_img_key, recibo_img_key, firma_img_key,
             recibo_pdf_key, contrato_pdf_key,
             created_at
        FROM ventas
       WHERE codigo=$1
       LIMIT 1
      `,
      [codigo],
    );
    return rows[0] ?? null;
  }

  // ===========================================================================
  // API pública
  // ===========================================================================

  /**
   * POST /v1/ventas
   * Crea una venta en estado "creada".
   */
  async crearVenta(dto: CrearVentaDto) {
    if (!dto?.cliente_nombre || !dto?.cliente_apellido || !dto?.documento || !dto?.plan) {
      throw new BadRequestException(
        'Faltan campos requeridos: cliente_nombre, cliente_apellido, documento, plan',
      );
    }
    if (dto.total === undefined || dto.total === null) {
      throw new BadRequestException('Falta total de la venta.');
    }

    const codigo = await this.nextCodigoVenta();
    // ⬇️ Fix: jamás enviar NULL a columnas NOT NULL
    const mensual_total = this.numOrNull(dto.mensual_total) ?? 0;
    const total = this.numOrNull(dto.total) ?? 0;

    // NOTA: usuario_id existe y no es NULL en tu entity; generamos un UUID libre.
    const rows = await this.ds.query(
      `
      INSERT INTO ventas
        (id, codigo, estado,
         cliente_nombre, cliente_apellido, documento, usuario_id,
         plan, mensual_total, total,
         created_at, updated_at)
      VALUES
        (gen_random_uuid(), $1, 'creada',
         $2, $3, $4, gen_random_uuid(),
         $5, $6, $7,
         now(), now())
      ON CONFLICT (codigo) DO NOTHING
      RETURNING id, codigo, estado
      `,
      [
        codigo,
        dto.cliente_nombre,
        dto.cliente_apellido,
        dto.documento,
        dto.plan,
        mensual_total,
        total,
      ],
    );

    if (!rows.length) {
      // Código colisionó (muy raro). Recupera existente.
      const exist = await this.ds.query(
        `SELECT id, codigo, estado FROM ventas WHERE codigo=$1`,
        [codigo],
      );
      return exist[0];
    }

    return rows[0];
  }

  /**
   * GET /v1/ventas?estado=creada|pagada
   */
  async listarVentas(filtro?: { estado?: string }) {
    const estado = filtro?.estado;
    const where = estado ? `WHERE estado = $1` : '';
    const params = estado ? [estado] : [];
    return this.ds.query(
      `
      SELECT codigo, estado,
             cliente_nombre, cliente_apellido, documento,
             plan, mensual_total, total,
             recibo_pdf_key, contrato_pdf_key,
             created_at
        FROM ventas
        ${where}
       ORDER BY created_at DESC
       LIMIT 200
      `,
      params,
    );
  }

  /**
   * GET /v1/ventas/:codigo
   * Devuelve venta + (si existe) orden INS asociada no anulada.
   */
  async detalleVenta(codigo: string) {
    const v = await this.getVentaByCodigo(codigo);
    if (!v) throw new NotFoundException('Venta no encontrada');

    const ord = await this.ds.query(
      `
      SELECT id, codigo, estado, tipo,
             agendado_para AS "agendadoPara",
             tecnico_id    AS "tecnicoId"
        FROM ordenes
       WHERE venta_id = $1
         AND tipo = 'INS'
         AND estado <> 'anulada'
       ORDER BY created_at DESC
       LIMIT 1
      `,
      [v.id],
    );
    const orden = ord[0] ?? null;

    return {
      venta: {
        codigo: v.codigo,
        estado: v.estado,
        cliente_nombre: v.cliente_nombre,
        cliente_apellido: v.cliente_apellido,
        documento: v.documento,
        plan: v.plan,
        mensual_total: v.mensual_total,
        total: v.total,
        recibo_pdf_key: v.recibo_pdf_key ?? null,
        contrato_pdf_key: v.contrato_pdf_key ?? null,
        evidencias: {
          cedula_img_key: v.cedula_img_key ?? null,
          recibo_img_key: v.recibo_img_key ?? null,
          firma_img_key: v.firma_img_key ?? null,
        },
        created_at: v.created_at,
      },
      orden,
    };
  }

  /**
   * POST /v1/ventas/:codigo/evidencias
   * Guarda claves (keys) de imágenes en la fila de ventas.
   */
  async subirEvidencias(codigo: string, dto: EvidenciasDto) {
    const v = await this.getVentaByCodigo(codigo);
    if (!v) throw new NotFoundException('Venta no encontrada');

    await this.ds.query(
      `
      UPDATE ventas
         SET cedula_img_key = COALESCE($2, cedula_img_key),
             recibo_img_key = COALESCE($3, recibo_img_key),
             firma_img_key  = COALESCE($4, firma_img_key),
             updated_at     = now()
       WHERE id=$1
      `,
      [v.id, dto.cedula_key ?? null, dto.recibo_key ?? null, dto.firma_key ?? null],
    );

    const nv = await this.getVentaByCodigo(codigo);
    return {
      codigo: nv.codigo,
      estado: nv.estado,
      cedula_img_key: nv.cedula_img_key ?? null,
      recibo_img_key: nv.recibo_img_key ?? null,
      firma_img_key: nv.firma_img_key ?? null,
    };
  }

  /**
   * POST /v1/ventas/:codigo/asegurar-ins
   * Crea (si no hay) la orden INS asociada a la venta (estado 'pendiente').
   */
  async asegurarIns(codigo: string) {
    const v = await this.getVentaByCodigo(codigo);
    if (!v) throw new NotFoundException('Venta no encontrada');

    let orden =
      (
        await this.ds.query(
          `
          SELECT id, codigo, estado, tipo,
                 agendado_para AS "agendadoPara",
                 tecnico_id    AS "tecnicoId"
            FROM ordenes
           WHERE venta_id = $1
             AND tipo='INS'
             AND estado <> 'anulada'
           LIMIT 1
          `,
          [v.id],
        )
      )[0] ?? null;

    if (!orden) {
      const nextNumRow = await this.ds.query(
        `
        SELECT LPAD(
                 COALESCE(MAX(CASE WHEN codigo LIKE 'INS-%'
                                   THEN SUBSTR(codigo,5)::int END) + 1, 1)::text,
                 6, '0'
               ) AS seq
          FROM ordenes
        `,
      );
      const seq = nextNumRow?.[0]?.seq ?? '000001';
      const ordCodigo = `INS-${seq}`;

      const insertOrd = await this.ds.query(
        `
        INSERT INTO ordenes (id, codigo, tipo, estado, venta_id, created_at, updated_at)
        VALUES (gen_random_uuid(), $1, 'INS', 'pendiente', $2, now(), now())
        RETURNING id, codigo, estado, tipo,
                  agendado_para AS "agendadoPara",
                  tecnico_id    AS "tecnicoId"
        `,
        [ordCodigo, v.id],
      );
      orden = insertOrd[0];
    }

    return orden;
  }

  /**
   * POST /v1/ventas/:codigo/pagar
   * - Marca venta como 'pagada' (idempotente).
   * - Asegura INS (si no existe).
   */
  async pagarVenta(codigo: string) {
    const v = await this.getVentaByCodigo(codigo);
    if (!v) throw new NotFoundException('Venta no encontrada');

    let _idempotent = false;
    if (v.estado === 'pagada') {
      _idempotent = true;
    } else {
      await this.ds.query(
        `UPDATE ventas SET estado='pagada', updated_at=now() WHERE id=$1`,
        [v.id],
      );
    }

    const ins = await this.asegurarIns(codigo);

    const nv = await this.getVentaByCodigo(codigo);
    return {
      _idempotent,
      venta: {
        codigo: nv.codigo,
        estado: nv.estado as VentaEstado,
        recibo_pdf_key: nv.recibo_pdf_key ?? null,
        contrato_pdf_key: nv.contrato_pdf_key ?? null,
      },
      orden: ins
        ? {
            id: ins.id,
            codigo: ins.codigo,
            estado: ins.estado,
            tipo: 'INS',
            agendadoPara: ins.agendadoPara ?? null,
            tecnicoId: ins.tecnicoId ?? null,
          }
        : null,
    };
  }
}
