// src/modules/alertas/alerts.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { Cron } from '@nestjs/schedule';
import { lastValueFrom } from 'rxjs';
import { Pool } from 'pg';

type Severidad = 'info' | 'warning' | 'critical';

@Injectable()
export class AlertsService {
  private readonly logger = new Logger(AlertsService.name);
  private readonly pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl:
      (process.env.PGSSL || process.env.DATABASE_SSL)?.toLowerCase() === 'true'
        ? { rejectUnauthorized: false }
        : undefined,
  });

  constructor(private readonly http: HttpService) {}

  // ========= Helpers DB =========

  async listActive() {
    const { rows } = await this.pool.query(
      `SELECT id,tipo,clave,severidad,mensaje,payload,first_seen,last_seen
       FROM alertas
       WHERE activo = TRUE
       ORDER BY last_seen DESC`
    );
    return rows;
  }

  private async upsertAlert(
    tipo: string,
    clave: string,
    severidad: Severidad,
    mensaje: string,
    payload: any = {},
  ) {
    const q = `
      INSERT INTO alertas (tipo, clave, severidad, mensaje, payload, activo)
      VALUES ($1,$2,$3,$4,$5,TRUE)
      ON CONFLICT (tipo, clave) WHERE activo = TRUE
      DO UPDATE SET
        last_seen = now(),
        mensaje = EXCLUDED.mensaje,
        payload = EXCLUDED.payload,
        severidad = EXCLUDED.severidad
      RETURNING *`;
    await this.pool.query(q, [tipo, clave, severidad, mensaje, payload]);
    await this.maybeNotify(tipo, clave, severidad, mensaje, payload);
  }

  private async resolveAlert(tipo: string, clave: string) {
    const q = `UPDATE alertas
               SET activo = FALSE, last_seen = now()
               WHERE tipo = $1 AND clave = $2 AND activo = TRUE`;
    await this.pool.query(q, [tipo, clave]);
  }

  private async resolveAllByType(tipo: string) {
    const q = `UPDATE alertas
               SET activo = FALSE, last_seen = now()
               WHERE tipo = $1 AND activo = TRUE`;
    await this.pool.query(q, [tipo]);
  }

  private async maybeNotify(
    tipo: string,
    clave: string,
    severidad: Severidad,
    mensaje: string,
    payload: any,
  ) {
    const hook = process.env.ALERTS_SLACK_WEBHOOK;
    if (!hook) return;
    try {
      await lastValueFrom(
        this.http.post(hook, {
          text:
            `*[${severidad.toUpperCase()}]* ${tipo} (${clave})\n` +
            `${mensaje}\n` +
            '```' +
            JSON.stringify(payload, null, 2) +
            '```',
        }),
      );
    } catch (e: any) {
      this.logger.warn(`Slack webhook error: ${e?.message || e}`);
    }
  }

  // ========= Detectores =========

  /**
   * 1) PDF/MinIO probe
   * Envía un archivo tiny vía /v1/pdf/probe-put para validar que:
   * - la API responde
   * - el controller y MinIO reciben el objeto
   *
   * Hace fallback automático a /v1/v1/pdf/probe-put si aún tienes doble prefijo.
   */
  private async checkPdfProbe() {
    const clave = 'global';
    const base = (process.env.API_PUBLIC_URL || 'http://127.0.0.1:3000').replace(/\/+$/, '');
    const tryUrls = [
      `${base}/v1/pdf/probe-put`,
      `${base}/v1/v1/pdf/probe-put`, // fallback si hay doble v1 en tu bootstrap
    ];

    // payload mínimo válido para tu PdfController
    const key = 'alerts/probe.txt';
    const body = {
      data: 'data:text/plain;base64,SE9MQQo=', // "HOLA\n"
      contentType: 'text/plain',
    };

    let ok = false;
    let lastError: any = null;

    for (const url of tryUrls) {
      try {
        const resp = await lastValueFrom(
          this.http.post(`${url}?key=${encodeURIComponent(key)}`, body, { validateStatus: () => true }),
        );
        if (resp.status === 200 && resp.data?.ok) {
          ok = true;
          break;
        } else {
          lastError = { status: resp.status, data: resp.data };
        }
      } catch (e: any) {
        lastError = e?.message || String(e);
      }
    }

    if (ok) {
      await this.resolveAlert('pdf.minio.down', clave);
    } else {
      await this.upsertAlert(
        'pdf.minio.down',
        clave,
        'warning',
        'PDF/MinIO no disponible o probe falló',
        { error: lastError },
      );
    }
  }

  /**
   * 2a) Desviación espejo inv_tecnico
   */
  private async checkInvMirror() {
    const sql = `
      SELECT tecnico_id, material_id, stock_almacen, inv_tecnico,
             (stock_almacen - inv_tecnico) AS diff
      FROM v_desviacion_inv_tecnico
      WHERE (stock_almacen - inv_tecnico) <> 0
      LIMIT 50`;
    try {
      const { rows } = await this.pool.query(sql);
      if (rows.length === 0) {
        await this.resolveAllByType('inventario.espejo_diff');
        return;
      }
      for (const r of rows) {
        const clave = `${r.tecnico_id}:${r.material_id}`;
        const sev: Severidad = Math.abs(Number(r.diff)) >= 5 ? 'critical' : 'warning';
        const msg = `Espejo inventario desviado (Δ=${r.diff})`;
        await this.upsertAlert('inventario.espejo_diff', clave, sev, msg, r);
      }
    } catch (e: any) {
      await this.upsertAlert(
        'inventario.espejo_diff',
        'global',
        'warning',
        'Error al consultar v_desviacion_inv_tecnico',
        { error: e?.message || String(e) },
      );
    }
  }

  /**
   * 2b) Mismatch descuento consolidado (orden vs kardex) últimas 24h
   */
  private async checkOrdenMaterialesKardex() {
    const sql = `
      WITH om AS (
        SELECT o.codigo, SUM(om.cantidad) AS qty_esperada
        FROM ordenes o
        JOIN orden_materiales om ON om.orden_codigo = o.codigo
        WHERE o.estado = 'cerrada'
          AND om.descontado = TRUE
          AND o.cerrada_at >= now() - interval '24 hours'
        GROUP BY o.codigo
      ),
      kdx AS (
        SELECT ref_externa AS codigo, SUM(delta * -1) AS qty_kardex
        FROM v_kardex
        WHERE etiqueta = 'egreso'
          AND created_at >= now() - interval '24 hours'
        GROUP BY ref_externa
      )
      SELECT om.codigo,
             om.qty_esperada,
             COALESCE(kdx.qty_kardex, 0) AS qty_kardex,
             (COALESCE(kdx.qty_kardex, 0) - om.qty_esperada) AS diff
      FROM om
      LEFT JOIN kdx ON kdx.codigo = om.codigo
      WHERE (COALESCE(kdx.qty_kardex, 0) - om.qty_esperada) <> 0
      LIMIT 100;`;

    try {
      const { rows } = await this.pool.query(sql);
      if (rows.length === 0) {
        await this.resolveAllByType('inventario.descuento_mismatch');
        return;
      }
      for (const r of rows) {
        const clave = r.codigo as string;
        const sev: Severidad = Math.abs(Number(r.diff)) >= 2 ? 'critical' : 'warning';
        const msg = `Kardex no coincide con materiales descontados (diff=${r.diff})`;
        await this.upsertAlert('inventario.descuento_mismatch', clave, sev, msg, r);
      }
    } catch (e: any) {
      await this.upsertAlert(
        'inventario.descuento_mismatch',
        'global',
        'warning',
        'Error al cruzar orden_materiales vs v_kardex',
        { error: e?.message || String(e) },
      );
    }
  }

  // Corre cada 60s
  @Cron('*/60 * * * * *')
  async tick() {
    await this.checkPdfProbe();
    await this.checkInvMirror();
    await this.checkOrdenMaterialesKardex();
  }
}
