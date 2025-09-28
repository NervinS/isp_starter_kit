// src/modules/tecnicos/tecnicos.service.ts
import {
  Injectable,
  NotFoundException,
  ConflictException,
  Logger,
} from '@nestjs/common';
import { DataSource } from 'typeorm';
import { InventarioService } from '../inventario/inventario.service';
import { PdfService } from '../pdf/pdf.service';

type EstadoOrden = 'creada' | 'agendada' | 'en_progreso' | 'cerrada' | 'cancelada';

interface CerrarOrdenDto {
  materiales?: Array<{ materialIdInt?: number; materialId?: number | string; cantidad: number }>;
  evidenciasBase64?: string[];
  firmaBase64?: string;
}

@Injectable()
export class TecnicosService {
  private readonly log = new Logger('TecnicosService');
  // Verbosidad de evidencias (solo info); WARN/ERROR siempre salen
  private readonly evidLog = String(process.env.EVID_LOG || '0') === '1';
  // Límite de tamaño y MIMEs permitidos para evidencias
  private readonly MAX_IMG_BYTES = Number(process.env.EVID_MAX_BYTES || 10 * 1024 * 1024); // 10 MB
  private readonly ALLOWED_MIME = new Set(['image/png', 'image/jpeg', 'image/webp']);

  constructor(
    private readonly dataSource: DataSource,
    private readonly inventario: InventarioService,
    private readonly pdf: PdfService,
  ) {}

  private async getOrdenByCodigo(codigo: string) {
    const rows = await this.dataSource.query(
      `SELECT id,codigo,estado,usuario_id,tecnico_id,
              iniciada_at AS "iniciadaAt",
              cerrada_at  AS "cerradaAt"
       FROM ordenes WHERE codigo=$1 LIMIT 1`,
      [codigo],
    );
    return rows[0] ?? null;
  }

  private async getOrdenById(ordenId: string) {
    const rows = await this.dataSource.query(
      `SELECT id,codigo,estado,usuario_id,tecnico_id,
              iniciada_at AS "iniciadaAt",
              cerrada_at  AS "cerradaAt"
       FROM ordenes WHERE id=$1 LIMIT 1`,
      [ordenId], // <-- FIX del typo
    );
    return rows[0] ?? null;
  }

  private ensureTecnico(propietario: string | null, tecnicoId: string) {
    if (propietario && propietario !== tecnicoId) {
      throw new ConflictException('La orden no pertenece a este técnico.');
    }
  }

  async pendientes(tecnicoId: string) {
    return this.dataSource.query(
      `SELECT id,codigo,estado,usuario_id,tecnico_id,
              agendado_para AS "agendadoPara",turno,
              iniciada_at   AS "iniciadaAt"
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
    if (o.estado === 'cerrada' || o.estado === 'cancelada') {
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
    if (o.estado === 'cerrada' || o.estado === 'cancelada') {
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

  private async _cerrar(tecnicoId: string, codigo: string, dto: CerrarOrdenDto) {
    if (this.evidLog) this.log.log(`[TEC][EVID] _cerrar codigo=${codigo}`);

    const orden = await this.getOrdenByCodigo(codigo);
    if (!orden) throw new NotFoundException('Orden no encontrada');
    this.ensureTecnico(orden.tecnico_id ?? (orden as any).tecnicoId, tecnicoId);

    if (orden.estado === 'cerrada' || orden.estado === 'cancelada') {
      await this.safePut(`diag/last-cerrar.txt`, Buffer.from(`IDEMP ${codigo}\n`), 'text/plain');
      return { codigo, estado: orden.estado as EstadoOrden, cerradaAt: (orden as any).cerradaAt, pdfUrl: null, _idempotent: true };
    }

    const materiales = (dto.materiales ?? [])
      .map(m => [m.materialIdInt ?? (m.materialId !== undefined ? Number(m.materialId) : undefined), Number(m.cantidad)] as const)
      .filter(([id, cant]) => Number.isInteger(id) && (id as number) > 0 && Number.isFinite(cant) && cant > 0)
      .map(([id, cant]) => ({ materialIdInt: id as number, cantidad: cant }));

    const qr = this.dataSource.createQueryRunner();
    await qr.connect();
    await qr.startTransaction('READ COMMITTED');

    let ordenId!: string;
    try {
      const now = new Date().toISOString();
      const row = await qr.query(`SELECT id FROM ordenes WHERE codigo=$1 LIMIT 1`, [codigo]);
      if (!row.length) throw new NotFoundException('Orden no encontrada');
      ordenId = row[0].id;

      await qr.query(
        `UPDATE ordenes SET estado='cerrada', cerrada_at=$2 WHERE id=$1 AND estado<>'cerrada'`,
        [ordenId, now],
      );

      for (const m of materiales) {
        const upd = await qr.query(
          `UPDATE orden_materiales SET cantidad=cantidad+$3 WHERE orden_id=$1 AND material_id_int=$2 RETURNING 1`,
          [ordenId, m.materialIdInt, m.cantidad],
        );
        if (!upd.length) {
          await qr.query(
            `INSERT INTO orden_materiales(orden_id, material_id_int, cantidad) VALUES ($1,$2,$3)`,
            [ordenId, m.materialIdInt, m.cantidad],
          );
        }
      }

      await qr.commitTransaction();
    } catch (e) {
      await qr.rollbackTransaction();
      throw e;
    } finally {
      await qr.release();
    }

    for (const m of materiales) {
      try {
        await this.inventario.descontarStock(
          tecnicoId,
          {
            materialIdInt: m.materialIdInt,
            cantidad: m.cantidad,
            refExterna: `om:${codigo}:${m.materialIdInt}`,
            motivo: `cierre-orden:${codigo}`,
          },
          tecnicoId,
        );
        await this.dataSource.query(
          `UPDATE orden_materiales SET descontado=TRUE WHERE orden_id=$1 AND material_id_int=$2`,
          [ordenId, m.materialIdInt],
        );
      } catch (err) {
        this.log.warn(`[TEC][EVID] fallo descuento stock om:${codigo}:${m.materialIdInt} -> ${String(err)}`);
      }
    }

    try {
      await this.persistirEvidenciasBestEffort(codigo, dto);
    } catch (e) {
      this.log.warn(`[TEC][EVID] persistir evidencias fallo codigo=${codigo} -> ${String(e)}`);
    }

    await this.safePut(`diag/last-cerrar.txt`, Buffer.from(`OK ${codigo}\n`), 'text/plain');

    return { codigo, estado: 'cerrada' as EstadoOrden, cerradaAt: new Date().toISOString(), pdfUrl: null, _idempotent: false };
  }

  /**
   * Microfix:
   * - Si PdfService expone putObject(key, dataUrl, contentType, meta), pasamos la dataURL TAL CUAL.
   * - Si no existe, caemos a putObjectS3(key, Buffer) decodificando nosotros la dataURL.
   */
  private async persistirEvidenciasBestEffort(codigo: string, dto: CerrarOrdenDto) {
    const fotos = dto.evidenciasBase64 ?? [];
    const hasPutObject = typeof (this.pdf as any).putObject === 'function';
    const hasPutObjectS3 = typeof (this.pdf as any).putObjectS3 === 'function';

    // Firma (valida mime/tamaño)
    if (dto.firmaBase64) {
      const parsed = this.parseDataUrl(dto.firmaBase64);
      if (!parsed) {
        this.log.warn(`[TEC][EVID] firma inválida (dataURL)`);
      } else if (!this.ALLOWED_MIME.has(parsed.mime) || parsed.buf.length > this.MAX_IMG_BYTES) {
        this.log.warn(`[TEC][EVID] firma rechazada (mime=${parsed.mime} bytes=${parsed.buf.length})`);
      } else {
        const key = `firmas/${codigo}.png`; // mantenemos .png para no romper tests/rutas
        try {
          if (hasPutObject) {
            if (this.evidLog) this.log.log(`[TEC][EVID] usando putObject(dataURL) → ${key}`);
            await (this.pdf as any).putObject(key, dto.firmaBase64, parsed.mime, { 'Cache-Control': 'public, max-age=600' });
          } else if (hasPutObjectS3) {
            if (this.evidLog) this.log.log(`[TEC][EVID] usando putObjectS3(Buffer) → ${key} (${parsed.buf.length} bytes)`);
            await (this.pdf as any).putObjectS3(key, parsed.buf);
          } else {
            this.log.warn(`[TEC][EVID] NO hay putObject/putObjectS3 disponibles en PdfService`);
          }
        } catch (e) {
          this.log.warn(`[TEC][EVID] fallo subir firma ${key} -> ${String(e)}`);
        }
      }
    }

    // Fotos (valida mime/tamaño)
    for (let i = 0; i < fotos.length; i++) {
      const dataUrl = fotos[i];
      const parsed = this.parseDataUrl(dataUrl);
      if (!parsed) continue;
      if (!this.ALLOWED_MIME.has(parsed.mime) || parsed.buf.length > this.MAX_IMG_BYTES) {
        this.log.warn(`[TEC][EVID] foto ${i + 1} rechazada (mime=${parsed.mime} bytes=${parsed.buf.length})`);
        continue;
      }
      const key = `fotos/${codigo}/${i + 1}.png`; // mantenemos .png
      try {
        if (hasPutObject) {
          if (this.evidLog) this.log.log(`[TEC][EVID] usando putObject(dataURL) → ${key}`);
          await (this.pdf as any).putObject(key, dataUrl, parsed.mime, { 'Cache-Control': 'public, max-age=600' });
        } else if (hasPutObjectS3) {
          if (this.evidLog) this.log.log(`[TEC][EVID] usando putObjectS3(Buffer) → ${key} (${parsed.buf.length} bytes)`);
          await (this.pdf as any).putObjectS3(key, parsed.buf);
        } else {
          this.log.warn(`[TEC][EVID] NO hay putObject/putObjectS3 disponibles en PdfService para ${key}`);
        }
      } catch (e) {
        this.log.warn(`[TEC][EVID] fallo subir foto ${key} -> ${String(e)}`);
      }
    }
  }

  private dataUrlToBuffer(dataUrl: string): Buffer | null {
    const idx = String(dataUrl).indexOf('base64,');
    const b64 = idx >= 0 ? String(dataUrl).slice(idx + 'base64,'.length) : String(dataUrl);
    try { return Buffer.from(b64, 'base64'); } catch { return null; }
  }

  // Parser robusto de dataURL → {mime, buf}
  private parseDataUrl(dataUrl: string): { mime: string; buf: Buffer } | null {
    const s = String(dataUrl || '');
    const i = s.indexOf(',');
    if (i < 0) return null;
    const header = s.slice(0, i).toLowerCase(); // ej: data:image/png;base64
    const b64 = s.slice(i + 1);
    if (!header.startsWith('data:') || !header.includes('base64')) return null;
    const semi = header.indexOf(';');
    const mime = header.slice(5, semi >= 0 ? semi : undefined) || 'application/octet-stream';
    try { return { mime, buf: Buffer.from(b64, 'base64') }; } catch { return null; }
  }

  private async safePut(key: string, data: Buffer, contentType: string) {
    try {
      if (typeof (this.pdf as any).putObject === 'function') {
        // construir dataURL mínima para texto si se quiere pasar por putObject
        if (contentType.startsWith('text/')) {
          const b64 = data.toString('base64');
          const dataUrl = `data:${contentType};base64,${b64}`;
          await (this.pdf as any).putObject(key, dataUrl, contentType, { 'Cache-Control': 'public, max-age=60' });
        } else {
          // para binario genérico también formamos dataURL
          const b64 = data.toString('base64');
          const dataUrl = `data:${contentType};base64,${b64}`;
          await (this.pdf as any).putObject(key, dataUrl, contentType, { 'Cache-Control': 'public, max-age=600' });
        }
      } else if (typeof (this.pdf as any).putObjectS3 === 'function') {
        await (this.pdf as any).putObjectS3(key, data);
      } else {
        this.log.debug(`[TEC][EVID] safePut: PdfService no tiene putObject/putObjectS3`);
      }
    } catch (e) {
      this.log.debug(`[TEC][EVID] safePut fallo ${key}: ${String(e)}`);
    }
  }
}
