// src/modules/pdf/pdf.service.ts
import { Injectable, Logger } from '@nestjs/common';

type MinioClient = {
  statObject(bucket: string, key: string): Promise<any>;
  putObject(
    bucket: string,
    key: string,
    data: Buffer | string,
    size?: number,
    meta?: Record<string, string>,
  ): Promise<any>;
};

@Injectable()
export class PdfService {
  private readonly log = new Logger('PDF');

  private readonly bucket = process.env.MINIO_BUCKET || 'evidencias';
  private readonly publicBase = process.env.MINIO_PUBLIC_BASE || '';
  private readonly endpoint = process.env.MINIO_ENDPOINT || 'minio';
  private readonly port = process.env.MINIO_PORT ? Number(process.env.MINIO_PORT) : 9000;
  private readonly useSSL = String(process.env.MINIO_USE_SSL || 'false') === 'true';
  private readonly accessKey = process.env.MINIO_ROOT_USER || 'minioadmin';
  private readonly secretKey = process.env.MINIO_ROOT_PASSWORD || 'minioadmin';

  private minioCliPromise: Promise<MinioClient | null> | null = null;

  constructor() {
    this.log.log(
      `[init] bucket=${this.bucket} endpoint=${this.endpoint} ssl=${this.useSSL} publicBase=${this.publicBase} upload=enabled`,
    );
  }

  publicUrlFor(key: string) {
    if (!this.publicBase) return null;
    return `${this.publicBase}${key.replace(/^\/+/, '')}`;
  }

  private async loadMinio(): Promise<MinioClient | null> {
    if (!this.minioCliPromise) {
      this.minioCliPromise = (async () => {
        try {
          // Carga perezosa para no romper si no existe la dep en build locales
          const { Client } = await import('minio');
          const cli = new Client({
            endPoint: this.endpoint,
            port: this.port,
            useSSL: this.useSSL,
            accessKey: this.accessKey,
            secretKey: this.secretKey,
          }) as unknown as MinioClient;
          return cli;
        } catch (e: any) {
          this.log.error(
            `No se pudo cargar cliente MinIO en runtime (agrega dependencia 'minio'): ${e?.message || e}`,
          );
          return null;
        }
      })();
    }
    return this.minioCliPromise;
  }

  async exists(key: string): Promise<boolean> {
    const cli = await this.loadMinio();
    if (!cli) return false;
    try {
      await cli.statObject(this.bucket, key);
      return true;
    } catch {
      return false;
    }
  }

  // ===== MICROFIX: método genérico para subir firma/fotos =====
  /**
   * Sube un objeto a MinIO. Acepta:
   *  - Data URL base64 (p.ej. "data:image/png;base64,AAAA")
   *  - Buffer
   *
   * @param key         clave dentro del bucket (ej: "firmas/COD.png")
   * @param data        Data URL o Buffer
   * @param contentType Content-Type deseado (si dataURL lo trae, se respeta el del dataURL)
   * @param extraMeta   Metadatos HTTP extra (Cache-Control, etc.)
   */
  async putObject(
    key: string,
    data: string | Buffer,
    contentType?: string,
    extraMeta: Record<string, string> = {},
  ): Promise<void> {
    const cli = await this.loadMinio();
    if (!cli) {
      throw new Error(`MinIO no disponible en runtime`);
    }

    // Normaliza input a Buffer + content-type
    let body: Buffer;
    let ct: string | undefined = contentType;

    if (typeof data === 'string') {
      // ¿es data URL?
      const m = data.match(/^data:([^;,]+);base64,(.*)$/i);
      if (m) {
        ct = m[1] || contentType || 'application/octet-stream';
        try {
          body = Buffer.from(m[2], 'base64');
        } catch (e) {
          this.log.warn(`[putObject] dataURL inválido para ${key}: ${String(e)}`);
          throw e;
        }
      } else {
        // si te pasan string "crudo" (no dataURL), súbelo como tal
        body = Buffer.from(data, 'utf8');
        ct = contentType || 'text/plain';
      }
    } else {
      // Buffer
      body = data;
      ct = contentType || 'application/octet-stream';
    }

    const meta: Record<string, string> = {
      'Content-Type': ct,
      'Cache-Control': 'public, max-age=600',
      ...extraMeta,
    };

    const maxRetries = 3;
    let lastErr: any;
    for (let i = 1; i <= maxRetries; i++) {
      try {
        await cli.putObject(this.bucket, key, body, body.length, meta);
        return;
      } catch (e) {
        lastErr = e;
        this.log.warn(`[putObject] intento ${i}/${maxRetries} falló (${key}): ${e}`);
        if (i < maxRetries) await new Promise((r) => setTimeout(r, 200 * i));
      }
    }
    throw lastErr;
  }

  // ===== API actual para PDFs (se deja intacta) =====
  private async putObjectS3(key: string, body: Buffer): Promise<void> {
    const cli = await this.loadMinio();
    if (!cli) {
      throw new Error(`No se pudo cargar cliente MinIO en runtime (agrega dependencia 'minio')`);
    }
    const meta = {
      'Content-Type': 'application/pdf',
      'Cache-Control': 'public, max-age=600',
    };
    const maxRetries = 3;
    let lastErr: any;
    for (let i = 1; i <= maxRetries; i++) {
      try {
        await cli.putObject(this.bucket, key, body, body.length, meta);
        return;
      } catch (e) {
        lastErr = e;
        this.log.warn(`[putObjectS3] intento ${i}/${maxRetries} falló (${key}): ${e}`);
        if (i < maxRetries) await new Promise((r) => setTimeout(r, 200 * i));
      }
    }
    throw lastErr;
  }

  async ensurePdf(key: string): Promise<string | null> {
    const already = await this.exists(key);
    if (!already) {
      const minimalPdf = Buffer.from('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n', 'utf8');
      try {
        await this.putObjectS3(key, minimalPdf);
      } catch (e: any) {
        this.log.error(`Falló subida S3 (no detiene el cierre): ${e?.message || e}`);
      }
    }
    return this.publicUrlFor(key);
  }

  async renderAndStore(key: string, _data: unknown): Promise<string | null> {
    // Implementación mínima: garantiza que el PDF exista.
    return this.ensurePdf(key);
  }
}
