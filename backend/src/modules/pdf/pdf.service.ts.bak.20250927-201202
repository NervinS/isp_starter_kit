// src/modules/pdf/pdf.service.ts
import { Injectable, Logger } from '@nestjs/common';

type MinioClient = {
  putObject: (
    bucket: string,
    key: string,
    body: Buffer,
    size: number,
    meta?: Record<string, string>,
  ) => Promise<any>;
  statObject: (bucket: string, key: string) => Promise<any>;
};

@Injectable()
export class PdfService {
  private readonly log = new Logger('PDF');

  private readonly bucket = process.env.MINIO_BUCKET || 'evidencias';
  private readonly publicBase = process.env.MINIO_PUBLIC_BASE || '';
  private readonly endpoint = process.env.MINIO_ENDPOINT || 'minio';
  private readonly port =
    process.env.MINIO_PORT ? Number(process.env.MINIO_PORT) : 9000;
  private readonly useSSL = String(process.env.MINIO_USE_SSL || 'false') === 'true';
  private readonly accessKey = process.env.MINIO_ROOT_USER || 'minioadmin';
  private readonly secretKey = process.env.MINIO_ROOT_PASSWORD || 'minioadmin';

  private minioCliPromise: Promise<MinioClient | null> | null = null;

  constructor() {
    this.log.log(
      `[init] bucket=${this.bucket} endpoint=${this.endpoint} ssl=${this.useSSL} publicBase=${this.publicBase} upload=enabled`,
    );
  }

  /** URL pública (o null si no hay base definida) */
  publicUrlFor(key: string): string | null {
    if (!this.publicBase) return null;
    // publicBase debe terminar en "/"
    return `${this.publicBase}${key.replace(/^\/+/, '')}`;
  }

  /** Carga perezosa del cliente MinIO */
  private async loadMinio(): Promise<MinioClient | null> {
    if (!this.minioCliPromise) {
      this.minioCliPromise = (async () => {
        try {
          const { Client } = await import('minio'); // v7.x
          const cli = new Client({
            endPoint: this.endpoint,
            port: this.port,
            useSSL: this.useSSL,
            accessKey: this.accessKey,
            secretKey: this.secretKey,
          });
          return cli as unknown as MinioClient;
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

  /** Verifica existencia del objeto */
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

  /** Sube un buffer como application/pdf con reintentos y Cache-Control */
  private async putObjectS3(key: string, body: Buffer): Promise<void> {
    const cli = await this.loadMinio();
    if (!cli) {
      throw new Error(
        "No se pudo cargar cliente MinIO en runtime (agrega dependencia 'minio')",
      );
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
        this.log.warn(`[putObject] intento ${i}/${maxRetries} falló: ${e}`);
        if (i < maxRetries) await new Promise((r) => setTimeout(r, 200 * i));
      }
    }
    throw lastErr;
  }

  /**
   * Genera y asegura un PDF “dummy” si no existe, y devuelve URL pública (o null).
   * Idempotente: si ya existe, solo devuelve la URL.
   */
  async ensurePdf(key: string): Promise<string | null> {
    const already = await this.exists(key);
    if (!already) {
      const minimalPdf = Buffer.from(
        '%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n',
        'utf8',
      );
      try {
        await this.putObjectS3(key, minimalPdf);
      } catch (e: any) {
        this.log.error(
          `Falló subida S3 (no detiene el cierre): ${e?.message || e}`,
        );
        // No relanzamos: el cierre de negocio no se bloquea
      }
    }
    return this.publicUrlFor(key);
  }

  /**
   * Compat: controladores antiguos pueden llamar a renderAndStore(key)
   * Hace lo mismo que ensurePdf(key).
   */
  async renderAndStore(key: string, _data?: Buffer | string): Promise<string | null> {
    return this.ensurePdf(key);
  }
}
