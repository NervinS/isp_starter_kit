// src/modules/tecnicos/tecnicos.service.ts
import {
  Injectable,
  NotFoundException,
  ConflictException,
  Logger,
  Inject,
  forwardRef,
} from '@nestjs/common';
import { DataSource, QueryRunner } from 'typeorm';
import { PdfService } from '../pdf/pdf.service';
import { consolidateMaterials } from '../../common/utils/inventario';
import * as crypto from 'crypto';

type EstadoOrden = 'creada' | 'agendada' | 'en_progreso' | 'cerrada' | 'cancelada';

interface CerrarOrdenDto {
  materiales?: Array<{ materialIdInt?: number; materialId?: number | string; cantidad: number }>;
  evidenciasBase64?: string[];
  firmaBase64?: string;
}

@Injectable()
export class TecnicosService {
  private readonly log = new Logger('TecnicosService');
  private readonly evidLog =
    String(process.env.EVID_LOG || (process.env.NODE_ENV !== 'production' ? '1' : '0')) === '1';

  constructor(
    private readonly dataSource: DataSource,
    @Inject(forwardRef(() => PdfService))
    private readonly pdf: PdfService,
  ) {}

  // ===== helpers =====
  private async getOrdenByCodigo(codigo: string) {
    const rows = await this.dataSource.query(
      `SELECT id,codigo,tipo,estado,usuario_id,tecnico_id,
              iniciada_at AS "iniciadaAt",
              cerrada_at  AS "cerradaAt"
       FROM ordenes WHERE codigo=$1 LIMIT 1`,
      [codigo],
    );
    return rows[0] ?? null;
  }
  private async getOrdenById(id: string) {
    const rows = await this.dataSource.query(
      `SELECT id,codigo,tipo,estado,usuario_id,tecnico_id,
              iniciada_at AS "iniciadaAt",
              cerrada_at  AS "cerradaAt"
       FROM ordenes WHERE id=$1 LIMIT 1`,
      [id],
    );
    return rows[0] ?? null;
  }
  private ensureTecnico(propietario: string | null, tecnicoId: string) {
    if (propietario && propietario !== tecnicoId) {
      throw new ConflictException('La orden no pertenece a este técnico.');
    }
  }
  private async getAlmacenTecnicoId(tecnicoId: string, qr: QueryRunner): Promise<string> {
    const r = await qr.query(
      `SELECT id FROM almacenes WHERE tipo='tecnico' AND tecnico_id=$1 LIMIT 1`,
      [tecnicoId],
    );
    if (!r.length) throw new NotFoundException('Almacén técnico no encontrado');
    return r[0].id as string;
  }
  private buildCloseIdemKey(codigo: string, items: { materialIdInt: number; cantidad: number }[]) {
    const norm = items
      .slice()
      .sort((a, b) => a.materialIdInt - b.materialIdInt)
      .map(x => `${x.materialIdInt}:${x.cantidad}`)
      .join('|');
    return `close:${codigo}:${crypto.createHash('sha256').update(norm).digest('hex')}`;
  }

  // ===== públicas =====
  pendientes(tecnicoId: string) {
    return this.dataSource.query(
      `SELECT id,codigo,estado,usuario_id,tecnico_id,
              agendado_para AS "agendadoPara",turno,iniciada_at AS "iniciadaAt"
         FROM ordenes
        WHERE tecnico_id=$1 AND estado IN ('agendada','en_progreso')
        ORDER BY agendado_para NULLS LAST, created_at DESC`,
      [tecnicoId],
    );
  }

  async iniciarOrdenPorId(tecnicoId: string, ordenId: string) {
    const o = await this.getOrdenById(ordenId);
    if (!o) throw new NotFoundException('Orden no encontrada');
    this.ensureTecnico(o.tecnico_id ?? (o as any).tecnicoId, tecnicoId);
    if (['cerrada', 'cancelada'].includes(o.estado)) {
      throw new ConflictException(`No se puede iniciar una orden en estado ${o.estado}`);
    }
    const now = new Date().toISOString();
    const rows = await this.dataSource.query(
      `UPDATE ordenes
          SET estado='en_progreso',
              iniciada_at = COALESCE(iniciada_at,$2)
        WHERE id=$1
      RETURNING codigo,estado,iniciada_at AS "iniciadaAt"`,
      [o.id, now],
    );
    const r = rows[0] ?? { codigo: o.codigo, estado: o.estado, iniciadaAt: (o as any).iniciadaAt };
    return { codigo: r.codigo, estado: r.estado, iniciadaAt: r.iniciadaAt, _idempotent: o.estado === 'en_progreso' };
  }

  async iniciarOrdenPorCodigo(tecnicoId: string, codigo: string) {
    const o = await this.getOrdenByCodigo(codigo);
    if (!o) throw new NotFoundException('Orden no encontrada');
    this.ensureTecnico(o.tecnico_id ?? (o as any).tecnicoId, tecnicoId);
    if (['cerrada', 'cancelada'].includes(o.estado)) {
      throw new ConflictException(`No se puede iniciar una orden en estado ${o.estado}`);
    }
    const now = new Date().toISOString();
    const rows = await this.dataSource.query(
      `UPDATE ordenes
          SET estado='en_progreso',
              iniciada_at = COALESCE(iniciada_at,$2)
        WHERE codigo=$1
      RETURNING codigo,estado,iniciada_at AS "iniciadaAt"`,
      [codigo, now],
    );
    const r = rows[0] ?? { codigo: o.codigo, estado: o.estado, iniciadaAt: (o as any).iniciadaAt };
    return { codigo: r.codigo, estado: r.estado, iniciadaAt: r.iniciadaAt, _idempotent: o.estado === 'en_progreso' };
  }

  iniciarPorCodigo(tecnicoId: string, codigo: string) {
    return this.iniciarOrdenPorCodigo(tecnicoId, codigo);
  }

  async cerrarOrdenPorId(tecnicoId: string, ordenId: string, dto: CerrarOrdenDto = {}) {
    const o = await this.getOrdenById(ordenId);
    if (!o) throw new NotFoundException('Orden no encontrada');
    this.ensureTecnico(o.tecnico_id ?? (o as any).tecnicoId, tecnicoId);
    return this._cerrar(tecnicoId, o.codigo, dto);
  }

  async cerrarOrdenPorCodigo(tecnicoId: string, codigo: string, dto: CerrarOrdenDto = {}) {
    const o = await this.getOrdenByCodigo(codigo);
    if (!o) throw new NotFoundException('Orden no encontrada');
    this.ensureTecnico(o.tecnico_id ?? (o as any).tecnicoId, tecnicoId);
    return this._cerrar(tecnicoId, codigo, dto);
  }

  cerrarPorCodigo(tecnicoId: string, codigo: string, dto: CerrarOrdenDto = {}) {
    return this.cerrarOrdenPorCodigo(tecnicoId, codigo, dto);
  }

  // ===== cierre atómico =====
  private async _cerrar(tecnicoId: string, codigo: string, dto: CerrarOrdenDto) {
    this.log.log(`[TEC][EVID] _cerrar codigo=${codigo}`);

    // normaliza materiales y consolida
    const items = (dto.materiales ?? [])
      .map(m => {
        const id = m.materialIdInt ?? (m.materialId !== undefined ? Number(m.materialId) : undefined);
        return [id, Number(m.cantidad)] as const;
      })
      .filter(([id, cant]) => Number.isInteger(id) && (id as number) > 0 && Number.isFinite(cant) && cant > 0)
      .map(([id, cant]) => ({ materialIdInt: id as number, cantidad: Math.trunc(cant) }));

    const consolidados = consolidateMaterials(items);

    const qr = this.dataSource.createQueryRunner();
    await qr.connect();
    await qr.startTransaction('SERIALIZABLE');

    try {
      // 1) bloquear orden
      const row = await qr.query(
        `SELECT id,codigo,tipo,estado,usuario_id,tecnico_id
           FROM ordenes
          WHERE codigo=$1
          FOR UPDATE`,
        [codigo],
      );
      if (!row.length) throw new NotFoundException('Orden no encontrada');
      const orden = row[0];

      if (['cerrada', 'cancelada'].includes(orden.estado)) {
        await qr.rollbackTransaction();
        return { codigo, estado: orden.estado as EstadoOrden, cerradaAt: new Date().toISOString(), pdfUrl: null, _idempotent: true };
      }

      // 2) idempotencia por set consolidado
      const idemKey = this.buildCloseIdemKey(codigo, consolidados);
      await qr.query(
        `CREATE TABLE IF NOT EXISTS idem_requests(
          key text PRIMARY KEY,
          created_at timestamptz NOT NULL DEFAULT now()
        )`,
      );
      const ins = await qr.query(
        `INSERT INTO idem_requests(key) VALUES ($1)
           ON CONFLICT (key) DO NOTHING
         RETURNING key`,
        [idemKey],
      );
      if (!ins.length) {
        await qr.rollbackTransaction();
        return { codigo, estado: 'cerrada' as EstadoOrden, cerradaAt: new Date().toISOString(), pdfUrl: null, _idempotent: true };
      }

      // 3) upsert OM consolidado (una fila por material) usando material_id
      for (const m of consolidados) {
        await qr.query(
          `INSERT INTO orden_materiales(orden_id, material_id, cantidad, descontado)
           VALUES ($1,$2,$3,FALSE)
           ON CONFLICT (orden_id, material_id)
           DO UPDATE SET cantidad = orden_materiales.cantidad + EXCLUDED.cantidad,
                         updated_at = now()`,
          [orden.id, m.materialIdInt, m.cantidad],
        );
      }

      // 4) DESCUENTO ROBUSTO: derivar el total a descontar desde la BD (fuente de verdad)
      //    Esto evita cualquier delta entre consolidación en memoria vs persistencia.
      const mats: Array<{ material_id: number; total: number }> = await qr.query(
        `SELECT material_id, SUM(cantidad)::int AS total
           FROM orden_materiales
          WHERE orden_id=$1
          GROUP BY material_id`,
        [orden.id],
      );

      // 4.1 localizar almacén técnico
      const almacenTecId = await this.getAlmacenTecnicoId(tecnicoId, qr);

      for (const m of mats) {
        const materialId = Number(m.material_id);
        const req = Number(m.total);

        // 4.2 lock y verificación de saldo
        const stk = await qr.query(
          `SELECT cantidad FROM stock_almacen
            WHERE almacen_id=$1 AND material_id=$2
            FOR UPDATE`,
          [almacenTecId, materialId],
        );
        const saldo = Number(stk?.[0]?.cantidad ?? 0);
        if (saldo < req) {
          throw new ConflictException(`Saldo insuficiente en técnico para material=${materialId} (saldo=${saldo}, req=${req})`);
        }

        // 4.3 descuenta stock_almacen
        await qr.query(
          `UPDATE stock_almacen
              SET cantidad = cantidad - $1
            WHERE almacen_id=$2 AND material_id=$3`,
          [req, almacenTecId, materialId],
        );

        // 4.4 espejo inv_tecnico: upsert con delta en una sola sentencia
        await qr.query(
          `INSERT INTO inv_tecnico (tecnico_id, material_id, cantidad)
           VALUES ($1,$2,$3) -- insert como -req
           ON CONFLICT (tecnico_id, material_id)
           DO UPDATE SET cantidad = inv_tecnico.cantidad - EXCLUDED.cantidad`,
          [tecnicoId, materialId, req],
        );

        // 4.5 kardex (egreso total por material)
        await qr.query(
          `INSERT INTO kardex (almacen_id, material_id, delta, etiqueta, created_at)
           VALUES ($1,$2,$3,'egreso_cierre_man',now())`,
          [almacenTecId, materialId, -req],
        );

        // 4.6 marcar OM descontado
        await qr.query(
          `UPDATE orden_materiales
              SET descontado=TRUE, updated_at=now()
            WHERE orden_id=$1 AND material_id=$2`,
          [orden.id, materialId],
        );
      }

      // 5) cerrar orden
      await qr.query(`UPDATE ordenes SET estado='cerrada', cerrada_at=now() WHERE id=$1`, [orden.id]);

      await qr.commitTransaction();

      // 6) evidencias y estado_conexion (fuera de TX)
      try {
        await this.persistirEvidenciasBestEffort(codigo, dto);
      } catch (e) {
        this.log.warn(`[TEC][EVID] persistir evidencias fallo ${codigo}: ${String(e)}`);
      }
      try {
        const tipo = orden.tipo as string | undefined;
        if (tipo === 'COR') {
          await this.dataSource.query(`UPDATE usuarios SET estado_conexion='desconectado' WHERE id=$1`, [orden.usuario_id]);
        } else if (tipo === 'REC') {
          await this.dataSource.query(`UPDATE usuarios SET estado_conexion='conectado' WHERE id=$1`, [orden.usuario_id]);
        }
      } catch (e) {
        this.log.warn(`[TEC][EVID] no se pudo ajustar estado_conexion -> ${String(e)}`);
      }

      return { codigo, estado: 'cerrada' as EstadoOrden, cerradaAt: new Date().toISOString(), pdfUrl: null, _idempotent: false };
    } catch (e) {
      try { await qr.rollbackTransaction(); } catch {}
      throw e;
    } finally {
      try { await qr.release(); } catch {}
    }
  }

  // ===== evidencias =====
  private async persistirEvidenciasBestEffort(codigo: string, dto: CerrarOrdenDto) {
    if (!this.pdf) return;
    const fotos = dto.evidenciasBase64 ?? [];
    const hasPutObject = typeof (this.pdf as any).putObject === 'function';
    const hasPutObjectS3 = typeof (this.pdf as any).putObjectS3 === 'function';

    if (dto.firmaBase64) {
      const key = `firmas/${codigo}.png`;
      try {
        if (hasPutObject) {
          if (this.evidLog) this.log.log(`[TEC][EVID] putObject → ${key}`);
          await (this.pdf as any).putObject(key, dto.firmaBase64, 'image/png', { 'Cache-Control': 'public, max-age=600' });
        } else if (hasPutObjectS3) {
          const buf = this.dataUrlToBuffer(dto.firmaBase64);
          await (this.pdf as any).putObjectS3(key, buf);
        }
      } catch (e) {
        this.log.warn(`[TEC][EVID] fallo subir firma ${key}: ${String(e)}`);
      }
    }

    for (let i = 0; i < fotos.length; i++) {
      const key = `fotos/${codigo}/${i + 1}.png`;
      try {
        if (hasPutObject) {
          if (this.evidLog) this.log.log(`[TEC][EVID] putObject → ${key}`);
          await (this.pdf as any).putObject(key, fotos[i], 'image/png', { 'Cache-Control': 'public, max-age=600' });
        } else if (hasPutObjectS3) {
          const buf = this.dataUrlToBuffer(fotos[i]);
          await (this.pdf as any).putObjectS3(key, buf);
        }
      } catch (e) {
        this.log.warn(`[TEC][EVID] fallo subir foto ${key}: ${String(e)}`);
      }
    }
  }

  private dataUrlToBuffer(dataUrl: string): Buffer {
    const idx = String(dataUrl).indexOf('base64,');
    const b64 = idx >= 0 ? String(dataUrl).slice(idx + 'base64,'.length) : String(dataUrl);
    return Buffer.from(b64, 'base64');
  }
}
