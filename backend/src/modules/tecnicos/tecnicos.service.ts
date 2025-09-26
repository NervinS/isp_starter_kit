// src/modules/tecnicos/tecnicos.service.ts
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';
import { Orden } from '../ordenes/entities/orden.entity';
import { Tecnico } from './tecnico.entity';
import { InventarioService } from '../inventario/inventario.service';
import { PdfService } from '../pdf/pdf.service';
import { CerrarOrdenDto } from './dto/cerrar-orden.dto';

function stripDataUrl(input: string): string {
  return (input || '').replace(/^data:[^;]+;base64,/, '');
}

@Injectable()
export class TecnicosService {
  constructor(
    @InjectRepository(Orden) private readonly ordenRepo: Repository<Orden>,
    @InjectRepository(Tecnico) private readonly tecnicoRepo: Repository<Tecnico>,
    private readonly inv: InventarioService,
    private readonly pdf: PdfService,
    private readonly dataSource: DataSource,
  ) {}

  // ---------------------------------------------------------
  // Helpers privados
  // ---------------------------------------------------------

  /** Decodifica base64 seguro */
  private decodeBase64Safe(b64: string): Buffer {
    try {
      const clean = stripDataUrl(b64);
      return Buffer.from(clean, 'base64');
    } catch {
      throw new BadRequestException('Imagen/firma inválida (base64).');
    }
  }

  /** Cliente MinIO usando las mismas envs del contenedor */
  private getMinioClient() {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const Minio = require('minio');
    const endPoint = process.env.MINIO_ENDPOINT || 'minio';
    const port = Number(process.env.MINIO_PORT || 9000);
    const useSSL = String(process.env.MINIO_USE_SSL || 'false').toLowerCase() === 'true';
    const accessKey = process.env.MINIO_ACCESS_KEY || process.env.MINIO_ROOT_USER || 'minioadmin';
    const secretKey =
      process.env.MINIO_SECRET_KEY || process.env.MINIO_ROOT_PASSWORD || 'minioadmin';
    const client = new Minio.Client({ endPoint, port, useSSL, accessKey, secretKey });
    return client;
  }

  private getEvidenciasBucket(): string {
    return process.env.MINIO_BUCKET || process.env.MINIO_BUCKET_EVIDENCIAS || 'evidencias';
  }

  /** Asegura bucket (idempotente) */
  private async ensureBucketExists(client: any, bucket: string) {
    try {
      const exists = await client.bucketExists(bucket);
      if (!exists) await client.makeBucket(bucket);
    } catch (err) {
      const msg = (err as Error)?.message || String(err);
      if (!/previous request .* succeeded|already owned by you|exists/i.test(msg)) {
        throw new BadRequestException(`No se pudo asegurar bucket "${bucket}": ${msg}`);
      }
    }
  }

  /** Sube firma base64 a MinIO si viene y si la orden aún no tiene firma */
  private async ensureFirmaFromBase64IfNeeded(
    orden: Orden,
    firmaBase64?: string | null,
  ): Promise<void> {
    if (!firmaBase64 || (orden as any).firmaKey) return;

    const client = this.getMinioClient();
    const bucket = this.getEvidenciasBucket();
    await this.ensureBucketExists(client, bucket);

    const mime = (firmaBase64.match(/^data:(image\/[^;]+);base64,/) || [])[1] || 'image/png';
    const ext = mime.includes('jpeg') ? 'jpg' : (mime.split('/')[1] || 'png');
    const body = this.decodeBase64Safe(firmaBase64);

    // Key en BD sin prefijo del bucket
    const key = `firmas/${(orden as any).codigo}.${ext}`;
    await client.putObject(bucket, key, body, body.length, { 'Content-Type': mime });

    (orden as any).firmaKey = key;
  }

  /**
   * Sube evidencias (PNG/JPEG) a MinIO a partir de data URLs/base64.
   * Devuelve keys guardadas y actualiza orden.formData.evidenciasKeys.
   */
  private async ensureEvidenciasFromBase64IfNeeded(
    orden: Orden,
    evidenciasBase64?: string[] | null,
  ): Promise<string[] | undefined> {
    if (!evidenciasBase64 || evidenciasBase64.length === 0) return undefined;

    const client = this.getMinioClient();
    const bucket = this.getEvidenciasBucket();
    await this.ensureBucketExists(client, bucket);

    const keys: string[] = [];
    let idx = 0;
    for (const raw of evidenciasBase64) {
      if (!raw) continue;
      const mime = (raw.match(/^data:(image\/[^;]+);base64,/) || [])[1] || 'image/png';
      const ext = mime.includes('jpeg') ? 'jpg' : (mime.split('/')[1] || 'png');

      let buf: Buffer;
      try {
        buf = Buffer.from(stripDataUrl(raw), 'base64');
        if (buf.length === 0) continue;
      } catch {
        continue;
      }

      const key = `ordenes/${(orden as any).codigo}/${String(++idx)}.${ext}`;
      try {
        await client.putObject(bucket, key, buf, buf.length, { 'Content-Type': mime });
      } catch {
        // ignora fallos individuales
      }
      keys.push(key);
    }

    if (keys.length) {
      const formData = ((orden as any).formData as any) || {};
      formData.evidenciasKeys = keys;
      (orden as any).formData = formData;
      return keys;
    }
    return undefined;
  }

  /** Genera/asegura PDF (y actualiza pdfUrl si aplica) — defensivo con nombres */
  private async ensureOrdenPdf(
    orden: Orden,
    opts?: { refresh?: boolean; evidenciasKeys?: string[] },
  ): Promise<void> {
    const anyPdf: any = this.pdf as any;
    const candidates = [
      'ensureOrdenPdf',
      'ensure',
      'ensureOrden',
      'generarOrdenPdf',
      'generateOrdenPdf',
    ].filter((m) => typeof anyPdf?.[m] === 'function');

    if (candidates.length === 0) return;

    const method = candidates[0];
    const res = await anyPdf[method](orden, {
      refresh: opts?.refresh,
      evidenciasKeys: opts?.evidenciasKeys,
    });

    if (res?.pdfUrl) (orden as any).pdfUrl = res.pdfUrl;
  }

  // ---------------------------------------------------------
  // Público
  // ---------------------------------------------------------

  /** Listado de pendientes para un técnico */
  async pendientes(tecnicoId: string) {
    return this.ordenRepo.find({
      where: { tecnicoId, estado: 'agendada' as any },
      order: { createdAt: 'DESC' as any },
      take: 200,
    });
  }

  /** Iniciar por ID — idempotente */
  async iniciarOrdenPorId(tecnicoId: string, ordenId: string) {
    return this.dataSource.transaction(async (manager) => {
      const orden = await manager.findOne(Orden, { where: { id: ordenId } });
      if (!orden) throw new NotFoundException('Orden no existe');
      if ((orden as any).tecnicoId !== tecnicoId) {
        throw new ConflictException('Orden no pertenece al técnico');
      }
      if ((orden as any).estado === 'en_progreso') {
        return { codigo: (orden as any).codigo, estado: (orden as any).estado, _idempotent: true };
      }
      (orden as any).estado = 'en_progreso';
      (orden as any).iniciadaAt = new Date();
      await manager.save(orden);
      return {
        codigo: (orden as any).codigo,
        estado: (orden as any).estado,
        iniciadaAt: (orden as any).iniciadaAt,
        _idempotent: false,
      };
    });
  }

  /** Iniciar por código — alias */
  async iniciarOrdenPorCodigo(tecnicoId: string, codigo: string) {
    return this.iniciarPorCodigo(tecnicoId, codigo);
  }

  /** Iniciar por código — idempotente */
  async iniciarPorCodigo(tecnicoId: string, codigo: string) {
    const orden = await this.ordenRepo.findOne({ where: { codigo } });
    if (!orden) throw new NotFoundException('Orden no existe');
    if ((orden as any).tecnicoId !== tecnicoId) {
      throw new ConflictException('Orden no pertenece al técnico');
    }
    if ((orden as any).estado === 'en_progreso') {
      return { codigo, estado: (orden as any).estado, _idempotent: true };
    }
    (orden as any).estado = 'en_progreso';
    (orden as any).iniciadaAt = new Date();
    await this.ordenRepo.save(orden);
    return {
      codigo,
      estado: (orden as any).estado,
      iniciadaAt: (orden as any).iniciadaAt,
      _idempotent: false,
    };
  }

  /** Cerrar por ID — reusa cerrarPorCodigo */
  async cerrarOrdenPorId(tecnicoId: string, ordenId: string, dto: CerrarOrdenDto) {
    const orden = await this.ordenRepo.findOne({ where: { id: ordenId } });
    if (!orden) throw new NotFoundException('Orden no existe');
    return this.cerrarPorCodigo(tecnicoId, (orden as any).codigo, dto);
  }

  /** Cerrar por código — aplica materiales/firma/evidencias, PDF y estado_conexion */
  async cerrarPorCodigo(tecnicoId: string, codigo: string, dto: CerrarOrdenDto) {
    return await this.dataSource.transaction(async (manager) => {
      const orden = await manager.findOne(Orden, { where: { codigo } });
      if (!orden) throw new NotFoundException('Orden no existe');
      if ((orden as any).tecnicoId !== tecnicoId) {
        throw new ConflictException('Orden no pertenece al técnico');
      }

      const wasClosedBefore = Boolean((orden as any).cerradaAt);

      // -------- 1) Descuento de inventario (service si existe; si no, fallback SQL) --------
      const materiasRaw = (dto as any)?.materiales;
      const mats = Array.isArray(materiasRaw)
        ? materiasRaw
            .map((m: any) => ({
              id: Number(m.materialIdInt ?? m.materialId),
              qty: Number(m.cantidad ?? 0),
            }))
            .filter((m: any) => Number.isFinite(m.id) && m.id > 0 && Number.isFinite(m.qty) && m.qty > 0)
        : [];

      if (mats.length > 0) {
        const invAny: any = this.inv as any;
        if (typeof invAny?.descontarDeTecnico === 'function') {
          await invAny.descontarDeTecnico(tecnicoId, mats, manager);
        } else if (typeof invAny?.descontar === 'function') {
          await invAny.descontar(tecnicoId, mats, manager);
        } else {
          // Fallback: idempotente por (orden_id, material_id_int) sumado
          for (const m of mats) {
            const [{ already }] = await manager.query(
              `SELECT COALESCE(SUM(cantidad),0)::int AS already
                 FROM orden_materiales om
                 WHERE om.orden_id = $1 AND om.material_id_int = $2 AND om.descontado IS TRUE`,
              [(orden as any).id, m.id],
            );

            const remaining = Math.max(0, m.qty - Number(already || 0));
            if (remaining === 0) continue;

            // 1.1) registra movimiento de orden_materiales
            await manager.query(
              `INSERT INTO orden_materiales (id, orden_id, material_id, material_id_int, cantidad, descontado)
               VALUES (gen_random_uuid(), $1, gen_random_uuid(), $2, $3, TRUE)`,
              [(orden as any).id, m.id, remaining],
            );

            // 1.2) descuenta inventario del técnico mediante asiento negativo
            await manager.query(
              `INSERT INTO inv_tecnico (id, tecnico_id, material_id, cantidad)
               VALUES (gen_random_uuid(), $1, $2, $3 * -1)`,
              [tecnicoId, m.id, remaining],
            );
          }
        }
      }

      // -------- 2) Firma (opcional, base64) — sólo si no había --------
      await this.ensureFirmaFromBase64IfNeeded(orden, (dto as any)?.firmaBase64);

      // -------- 3) Cambia a cerrada si no estaba --------
      if (!wasClosedBefore) {
        (orden as any).estado = 'cerrada';
        (orden as any).cerradaAt = new Date();
      }

      // -------- 4) Evidencias (opcional) --------
      const evidenciasKeys = await this.ensureEvidenciasFromBase64IfNeeded(
        orden,
        (dto as any)?.evidenciasBase64,
      );

      // -------- 5) PDF --------
      await this.ensureOrdenPdf(orden, { evidenciasKeys });

      // -------- 6) Estado de conexión del usuario (COR → desconectado; REC/INS → conectado) --------
      if (!wasClosedBefore) {
        const [{ usuario_id, tipo }] = await manager.query(
          `SELECT usuario_id, tipo FROM ordenes WHERE id = $1`,
          [(orden as any).id],
        );

        if (tipo === 'COR') {
          await manager.query(
            `UPDATE usuarios SET estado_conexion='desconectado' WHERE id=$1`,
            [usuario_id],
          );
        } else if (tipo === 'REC' || tipo === 'INS') {
          await manager.query(
            `UPDATE usuarios SET estado_conexion='conectado' WHERE id=$1`,
            [usuario_id],
          );
        }
        // Otros tipos: sin cambio
      }

      await manager.save(orden);

      return {
        codigo: (orden as any).codigo,
        estado: (orden as any).estado,
        cerradaAt: (orden as any).cerradaAt ?? null,
        pdfUrl: (orden as any).pdfUrl ?? null,
        _idempotent: wasClosedBefore,
      };
    });
  }
}
