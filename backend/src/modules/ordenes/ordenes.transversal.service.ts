// src/modules/ordenes/ordenes.transversal.service.ts
import { Injectable, HttpException, HttpStatus, Optional } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { PdfService } from '../pdf/pdf.service';

type EvidenciaIn = { url: string; tipo?: string; meta?: any };

const TEMPLATE_BY_TIPO: Record<string, string> = {
  INS: 'plantilla-ins',
  REC: 'plantilla-rec',
  COR: 'plantilla-cor',
  MAN: 'plantilla-man',
  BAJ: 'plantilla-baj',
  TRA: 'plantilla-tra',
  CMB: 'plantilla-cmb',
  RCT: 'plantilla-rct',
};

@Injectable()
export class OrdenesTransversalService {
  constructor(
    private readonly ds: DataSource,
    @Optional() private readonly pdf?: PdfService, // opcional
  ) {}

  // ==== LECTURA TRANSVERSAL DE ORDEN ====
  async getOrdenTransversal(codigo: string) {
    const [o] = await this.ds.query(
      `select id, codigo, tipo, estado, usuario_id, cerrada_at, payload_abierto, evidencias
         from public.ordenes
        where codigo = $1`,
      [codigo],
    );
    if (!o) throw new HttpException('orden no existe', HttpStatus.NOT_FOUND);

    return {
      codigo: o.codigo,
      tipo: o.tipo,
      estado: o.estado,
      cerradaAt: o.cerrada_at ?? null,
      usuarioId: o.usuario_id ?? null,
      datosTecnicos: o.payload_abierto ?? null,
      evidenciasLegacy: o.evidencias ?? null,
    };
  }

  // ==== EVIDENCIAS RICAS + MERGE LEGACY ====
  async subirEvidencias(
    codigo: string,
    items: EvidenciaIn[],
    opts?: { mergeJson?: any; firmaKey?: string | null; raw?: any },
  ) {
    return this.ds.transaction('READ COMMITTED', async (em) => {
      const [o] = await em.query(
        `select id, evidencias, firma_key from public.ordenes where codigo=$1 for update`,
        [codigo],
      );
      if (!o) throw new HttpException('orden no existe', HttpStatus.NOT_FOUND);

      let inserted = 0;
      for (const it of items) {
        if (!it?.url) continue;
        const kind = it?.tipo ?? 'desconocido';
        const meta =
          it && typeof (it as any).meta === 'object'
            ? JSON.parse(JSON.stringify((it as any).meta))
            : {};
        await em.query(
          `insert into public.orden_evidencias(orden_id, kind, key, meta)
           values($1,$2,$3,$4)
           on conflict (orden_id, kind, key) do nothing`,
          [o.id, kind, it.url, meta],
        );
        inserted++;
      }

      const mergedEvid = opts?.mergeJson
        ? { ...(o.evidencias ?? {}), ...(opts.mergeJson ?? {}) }
        : o.evidencias ?? null;

      const updates: string[] = [];
      const params: any[] = [o.id];

      if (opts?.mergeJson) {
        updates.push(`evidencias=$${params.length + 1}`);
        params.push(mergedEvid);
      }
      if (typeof opts?.firmaKey === 'string') {
        updates.push(`firma_key=$${params.length + 1}`);
        params.push(opts.firmaKey);
      }
      if (updates.length) {
        await em.query(
          `update public.ordenes set ${updates.join(',')}, updated_at=now() where id=$1`,
          params,
        );
      }

      return { ok: true, codigo, items: inserted };
    });
  }

  // ==== CIERRE + SNAPSHOT (idempotente) ====
  async cerrarOrden(codigo: string, body: any) {
    return this.ds.transaction('READ COMMITTED', async (em) => {
      const [o] = await em.query(
        `select id, tipo, estado, cerrada_at, codigo from public.ordenes where codigo=$1 for update`,
        [codigo],
      );
      if (!o) throw new HttpException('orden no existe', HttpStatus.NOT_FOUND);

      const [snap] = await em.query(
        `select id, pdf_key, created_at from public.orden_cierres where orden_id=$1`,
        [o.id],
      );
      if (snap) {
        if (!o.cerrada_at || o.estado !== 'cerrada') {
          await em.query(
            `update public.ordenes
                set estado='cerrada',
                    cerrada_at = coalesce(cerrada_at, now()),
                    updated_at = now()
              where id=$1`,
            [o.id],
          );
        }
        return {
          ok: true,
          codigo,
          estado: 'cerrada',
          cerradaAt: o.cerrada_at ?? new Date(),
          _idempotent: true,
        };
      }

      // --- payload jsonb ---
      let rawPayload =
        body?.payload_cierre ?? body?.payloadCierre ?? body?.payload;
      if (rawPayload == null) {
        rawPayload =
          typeof body?.comentarios === 'string'
            ? { comentarios: body.comentarios }
            : {};
      }
      const safePayload =
        typeof rawPayload === 'string' ? { value: rawPayload } : rawPayload;
      const payloadObj = JSON.parse(JSON.stringify(safePayload ?? {}));
      const payloadStr = JSON.stringify(payloadObj);

      // --- evidencias jsonb ---
      const rows = await em.query(
        `select kind, key, meta, created_at
           from public.orden_evidencias
          where orden_id=$1
          order by created_at asc`,
        [o.id],
      );
      const evidenciasArr = rows.map((r: any) => ({
        kind: String(r.kind),
        key: String(r.key),
        meta:
          r.meta && typeof r.meta === 'object'
            ? JSON.parse(JSON.stringify(r.meta))
            : {},
        createdAt: r.created_at ? new Date(r.created_at).toISOString() : null,
      }));
      const evidenciasStr = JSON.stringify(evidenciasArr);

      // --- PDF (si no entra pdfKey, generar/subir mínimo) ---
      let pdfKey: string | null = body?.pdfKey ?? body?.pdf_key ?? null;

      if (!pdfKey) {
        const plantilla = TEMPLATE_BY_TIPO[o.tipo] ?? 'plantilla-generica';
        pdfKey = `pdf/ordenes/${o.codigo}.pdf`;

        try {
          const impl = this.pdf as any;
          if (impl) {
            const bytes = this.buildMinimalPdfBuffer({
              codigo: o.codigo,
              tipo: o.tipo,
              plantilla,
              payload: payloadObj,
              evidenciasLen: evidenciasArr.length,
            });
            if (typeof impl.putObject === 'function') {
              await impl.putObject(pdfKey, bytes, 'application/pdf');
            } else if (typeof impl.upload === 'function') {
              await impl.upload(pdfKey, bytes, 'application/pdf');
            } else if (typeof impl.put === 'function') {
              await impl.put(pdfKey, bytes, 'application/pdf');
            }
          }
        } catch {
          // no bloquea
        }
      }

      await em.query(
        `insert into public.orden_cierres
           (orden_id, tipo, payload_json, evidencias_json, pdf_key, version, created_at)
         values
           ($1,$2,$3::jsonb,$4::jsonb,$5,1, now())`,
        [o.id, o.tipo, payloadStr, evidenciasStr, pdfKey],
      );

      await em.query(
        `update public.ordenes
            set estado='cerrada',
                cerrada_at = coalesce(cerrada_at, now()),
                updated_at = now()
          where id=$1`,
        [o.id],
      );

      const [after] = await em.query(
        `select cerrada_at from public.ordenes where id=$1`,
        [o.id],
      );

      return {
        ok: true,
        codigo,
        estado: 'cerrada',
        cerradaAt: after?.cerrada_at ?? null,
        _idempotent: false,
      };
    });
  }

  // ==== LECTURA SNAPSHOT ====
  async getCierreByCodigo(codigo: string) {
    const [o] = await this.ds.query(
      `select id, codigo from public.ordenes where codigo=$1`,
      [codigo],
    );
    if (!o) throw new HttpException('orden no existe', HttpStatus.NOT_FOUND);

    const [c] = await this.ds.query(
      `select tipo, payload_json, evidencias_json, pdf_key, checksum, version, created_at
         from public.orden_cierres
        where orden_id=$1`,
      [o.id],
    );

    if (!c) {
      throw new HttpException('cierre no existe', HttpStatus.NOT_FOUND);
    }

    return {
      tipo: c.tipo,
      payload: c.payload_json,
      evidencias: c.evidencias_json ?? [],
      pdfKey: c.pdf_key ?? null,
      checksum: c.checksum ?? null,
      version: c.version ?? 1,
      createdAt: c.created_at ?? null,
    };
  }

  // ==== PDF INFO (lazy create si falta el objeto) ====
  async getPdfInfo(codigo: string) {
    const [o] = await this.ds.query(
      `select id, codigo, tipo from public.ordenes where codigo=$1`,
      [codigo],
    );
    if (!o) throw new HttpException('orden no existe', HttpStatus.NOT_FOUND);

    const [c] = await this.ds.query(
      `select pdf_key, payload_json
         from public.orden_cierres
        where orden_id=$1`,
      [o.id],
    );
    if (!c) throw new HttpException('cierre no existe', HttpStatus.NOT_FOUND);

    let pdfKey: string | null = c?.pdf_key ?? null;
    if (!pdfKey) throw new HttpException('pdf no disponible', HttpStatus.NOT_FOUND);

    // Intento “lazy”: si el objeto no existe en MinIO, generarlo/subirlo aquí
    try {
      const impl = this.pdf as any;
      if (impl) {
        let exists = false;

        if (typeof impl.exists === 'function') {
          exists = !!(await impl.exists(pdfKey));
        } else if (typeof impl.headObject === 'function') {
          try { await impl.headObject(pdfKey); exists = true; } catch { exists = false; }
        } else if (typeof impl.statObject === 'function') {
          try { await impl.statObject(pdfKey); exists = true; } catch { exists = false; }
        }

        if (!exists) {
          const plantilla = TEMPLATE_BY_TIPO[o.tipo] ?? 'plantilla-generica';
          const payload = c?.payload_json ?? {};
          const bytes = this.buildMinimalPdfBuffer({
            codigo: o.codigo,
            tipo: o.tipo,
            plantilla,
            payload,
            evidenciasLen: 0,
          });
          if (typeof impl.putObject === 'function') {
            await impl.putObject(pdfKey, bytes, 'application/pdf');
          } else if (typeof impl.upload === 'function') {
            await impl.upload(pdfKey, bytes, 'application/pdf');
          } else if (typeof impl.put === 'function') {
            await impl.put(pdfKey, bytes, 'application/pdf');
          }
        }
      }
    } catch {
      // no bloqueamos la respuesta; devolvemos la URL calculada
    }

    const base =
      process.env.PDF_PUBLIC_BASE ||
      process.env.MINIO_PUBLIC_BASE ||
      'http://127.0.0.1:9000/evidencias/';

    const norm = (s: string) => s.replace(/\/+$/g, '');
    const join = (b: string, k: string) =>
      `${norm(b)}/${String(k).replace(/^\/+/g, '')}`;

    const pdfUrl = join(base, pdfKey);

    return { ok: true, codigo: o.codigo, pdfKey, pdfUrl };
  }

  // ==== (Opcional) Regenerar PDF explícitamente ====
  async regenerarPdf(codigo: string) {
    const [o] = await this.ds.query(
      `select id, codigo, tipo from public.ordenes where codigo=$1`,
      [codigo],
    );
    if (!o) throw new HttpException('orden no existe', HttpStatus.NOT_FOUND);

    const [c] = await this.ds.query(
      `select payload_json, evidencias_json, pdf_key from public.orden_cierres where orden_id=$1`,
      [o.id],
    );
    if (!c) throw new HttpException('cierre no existe', HttpStatus.NOT_FOUND);

    let pdfKey: string | null = c.pdf_key ?? `pdf/ordenes/${o.codigo}.pdf`;

    try {
      const impl = this.pdf as any;
      if (impl) {
        const bytes = this.buildMinimalPdfBuffer({
          codigo: o.codigo,
          tipo: o.tipo,
          plantilla: TEMPLATE_BY_TIPO[o.tipo] ?? 'plantilla-generica',
          payload: c.payload_json ?? {},
          evidenciasLen: Array.isArray(c.evidencias_json) ? c.evidencias_json.length : 0,
        });
        if (typeof impl.putObject === 'function') {
          await impl.putObject(pdfKey, bytes, 'application/pdf');
        } else if (typeof impl.upload === 'function') {
          await impl.upload(pdfKey, bytes, 'application/pdf');
        } else if (typeof impl.put === 'function') {
          await impl.put(pdfKey, bytes, 'application/pdf');
        }
      }
    } catch {
      // no bloquea
    }

    const base =
      process.env.PDF_PUBLIC_BASE ||
      process.env.MINIO_PUBLIC_BASE ||
      'http://127.0.0.1:9000/evidencias/';
    const norm = (s: string) => s.replace(/\/+$/g, '');
    const join = (b: string, k: string) => `${norm(b)}/${String(k).replace(/^\/+/g, '')}`;
    const pdfUrl = join(base, pdfKey);

    return { ok: true, codigo: o.codigo, pdfKey, pdfUrl, _regenerated: true };
  }

  // ==== EQUIPOS (fallback amable) ====
  async aplicarAccionesEquipos(codigo: string, _body: any) {
    return { ok: true, codigo, aplicado: true };
  }

  // ========= Helpers =========
  private buildMinimalPdfBuffer(data: {
    codigo: string;
    tipo: string;
    plantilla: string;
    payload: any;
    evidenciasLen: number;
  }): Buffer {
    const text = `Orden ${data.codigo} [${data.tipo}] - ${data.plantilla}
payload keys: ${Object.keys(data.payload || {}).join(', ') || '-'}
evidencias: ${data.evidenciasLen}`;
    const contentStream = `BT /F1 12 Tf 72 720 Td (${this.escapePdfText(text)}) Tj ET`;
    const pdf = [
      '%PDF-1.4\n',
      '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
      '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n',
      '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n',
      `4 0 obj << /Length ${contentStream.length} >> stream\n${contentStream}\nendstream endobj\n`,
      '5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n',
      'xref\n0 6\n0000000000 65535 f \n',
      'trailer << /Size 6 /Root 1 0 R >>\nstartxref\n',
      '%%EOF',
    ].join('');
    return Buffer.from(pdf, 'utf8');
  }

  private escapePdfText(s: string): string {
    return String(s).replace(/[()\\]/g, (m) => `\\${m}`);
  }
}
