// src/modules/pdf/pdf.controller.ts
import {
  Controller,
  Get,
  Post,
  Query,
  Body,
  HttpCode,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { PdfService } from './pdf.service';

@Controller('pdf') // con globalPrefix('v1') → /v1/pdf (evita /v1/v1/pdf)
export class PdfController {
  constructor(private readonly pdf: PdfService) {}

  /**
   * Probe de salud del subsistema PDF/Storage.
   * Intenta escribir un objeto mínimo en el bucket para comprobar credenciales/bucket/ACL.
   * - 200 si OK
   * - 503 si falla (ideal para que el alertador levante alarma)
   *
   * GET /v1/pdf/probe
   *   ?mode=write|noop   (noop solo devuelve OK sin tocar storage; por defecto write)
   */
  @Get('probe')
  async probeGet(@Query('mode') mode = 'write') {
    if (mode === 'noop') {
      return { ok: true, mode, ts: new Date().toISOString() };
    }

    // Clave efímera (deja rastro mínimo si no hay lifecycle; aceptable para un healthcheck)
    const key = `_probe/${Date.now()}-health.txt`;
    const buf = Buffer.from('ok\n', 'utf8');

    try {
      await this.pdf.putObject(
        key,
        buf,
        'text/plain',
        {
          'Cache-Control': 'max-age=60, public',
          'x-probe': 'pdf-health',
        },
      );
      return { ok: true, key, size: buf.length, ts: new Date().toISOString() };
    } catch (e: any) {
      // Expone 503 para que el monitor lo detecte
      throw new HttpException(
        {
          ok: false,
          key,
          error: String(e?.message || e),
        },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
  }

  /**
   * Probe de escritura explícita (útil para pruebas manuales).
   * Permite enviar data en base64 (data:*;base64,...) y contentType opcional.
   *
   * POST /v1/pdf/probe-put?key=lo_que_quieras
   * body:
   *   { "data": "data:text/plain;base64,SE9MQQo=", "contentType": "text/plain" }
   */
  @Post('probe-put')
  @HttpCode(200)
  async probePut(@Query('key') key: string, @Body() body: any) {
    try {
      if (!key) {
        throw new Error('Falta query param ?key');
      }

      const raw = body?.data ?? 'data:text/plain;base64,SE9MQQo='; // "HOLA\n"
      const buf = (() => {
        // data URL → buffer
        const s = String(raw);
        const idx = s.indexOf(',');
        if (idx >= 0 && /base64/i.test(s.slice(0, idx))) {
          return Buffer.from(s.slice(idx + 1), 'base64');
        }
        return Buffer.isBuffer(raw) ? raw : Buffer.from(String(raw));
      })();

      await this.pdf.putObject(
        key,
        buf,
        body?.contentType || 'text/plain',
        { 'Cache-Control': 'public, max-age=60' },
      );
      return { ok: true, key, size: buf.length };
    } catch (e: any) {
      return { ok: false, key, error: String(e?.message || e) };
    }
  }
}
