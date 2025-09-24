import { Injectable, Logger } from '@nestjs/common';
import * as Minio from 'minio';
import { randomBytes } from 'crypto';

type ParsedEp = { endPoint: string; port: number; useSSL: boolean; origin: string };

function parseEndpoint(u?: string, fallback?: ParsedEp): ParsedEp {
  try {
    if (!u) throw new Error('no url');
    const url = new URL(u);
    const useSSL = url.protocol === 'https:';
    const port = url.port ? Number(url.port) : useSSL ? 443 : 80;
    return { endPoint: url.hostname, port, useSSL, origin: `${url.protocol}//${url.host}` };
  } catch {
    if (fallback) return fallback;
    return { endPoint: '127.0.0.1', port: 9000, useSSL: false, origin: 'http://127.0.0.1:9000' };
  }
}

function extFromMime(m?: string) {
  if (!m) return 'bin';
  if (m.includes('jpeg')) return 'jpg';
  if (m.includes('png')) return 'png';
  if (m.includes('webp')) return 'webp';
  if (m.includes('pdf')) return 'pdf';
  return 'bin';
}

@Injectable()
export class MinioService {
  private readonly log = new Logger(MinioService.name);

  private readonly bucket = process.env.MINIO_BUCKET || 'evidencias';
  private readonly region = process.env.MINIO_REGION || 'us-east-1';

  private readonly mcInternal: Minio.Client;
  private readonly mcPublic: Minio.Client;

  private readonly internalOrigin: string;
  private readonly publicOrigin: string;

  constructor() {
    const accessKey = process.env.MINIO_ACCESS_KEY || 'minioadmin';
    const secretKey = process.env.MINIO_SECRET_KEY || 'minioadmin';

    const internalEp = parseEndpoint(
      process.env.MINIO_ENDPOINT,
      parseEndpoint(
        `${process.env.MINIO_USE_SSL === 'true' ? 'https' : 'http'}://${process.env.MINIO_HOST || '127.0.0.1'}:${process.env.MINIO_PORT || '9000'}`
      ),
    );
    const publicEp = parseEndpoint(
      process.env.MINIO_EXTERNAL_URL || process.env.MINIO_PUBLIC_ENDPOINT,
      internalEp,
    );

    this.internalOrigin = internalEp.origin;
    this.publicOrigin = publicEp.origin;

    this.mcInternal = new Minio.Client({
      endPoint: internalEp.endPoint,
      port: internalEp.port,
      useSSL: internalEp.useSSL,
      accessKey,
      secretKey,
    });

    this.mcPublic = new Minio.Client({
      endPoint: publicEp.endPoint,
      port: publicEp.port,
      useSSL: publicEp.useSSL,
      accessKey,
      secretKey,
    });

    this.ensureBucket().catch(err =>
      this.log.error(`No se pudo asegurar bucket "${this.bucket}": ${err?.message || err}`),
    );
  }

  private async ensureBucket() {
    const exists = await this.mcInternal.bucketExists(this.bucket).catch(() => false);
    if (!exists) {
      await this.mcInternal.makeBucket(this.bucket, this.region);
      this.log.log(`Bucket creado: ${this.bucket} (${this.region})`);
    }
  }

  async saveBuffer(buf: Buffer, key: string, contentType?: string) {
// Asegura que sea Buffer y calcula el size:
const data: Buffer = Buffer.isBuffer(buf) ? buf : Buffer.from(buf);

await this.mcInternal.putObject(
  this.bucket,
  key,
  data,
  data.length, // <--- size obligatorio
  { 'Content-Type': contentType || 'application/octet-stream' }, // <--- metadatos
);

    return { objectKey: key, mime: contentType, size: buf.length };
  }

  async saveBase64(dataUrl: string, prefix: string) {
    const m = dataUrl.match(/^data:([^;]+);base64,(.+)$/i);
    if (!m) throw new Error('DataURL inválido');
    const mime = m[1];
    const b64 = m[2];
    const buf = Buffer.from(b64, 'base64');
    const name = `${prefix.replace(/\/+$/,'')}/${Date.now()}-${randomBytes(4).toString('hex')}.${extFromMime(mime)}`;
    await this.saveBuffer(buf, name, mime);
    return { objectKey: name, mime, size: buf.length };
  }

  /** Descarga a Buffer (para estampar firma en el PDF) */
  async getObjectBuffer(key: string): Promise<Buffer> {
    const stream = await this.mcInternal.getObject(this.bucket, key);
    const chunks: Buffer[] = [];
    return await new Promise<Buffer>((resolve, reject) => {
      stream.on('data', (c: Buffer) => chunks.push(c));
      stream.on('error', reject);
      stream.on('end', () => resolve(Buffer.concat(chunks)));
    });
  }

  /** URL firmada con el host público (NAT) */
  async getSignedUrl(key: string, expirySeconds = 3600): Promise<string> {
    return await this.mcPublic.presignedGetObject(this.bucket, key, expirySeconds);
  }
}
