// src/modules/ordenes/controllers/tecnicos-cierre.controller.ts
import { Controller, Post, Param, Body, Logger } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { PdfService } from '../../pdf/pdf.service';

@Controller('tecnicos/:tecnicoId/ordenes/codigo')
export class TecnicosCierreController {
  private readonly logger = new Logger('[TEC-CLOSE]');

  constructor(
    private readonly db: DataSource,
    private readonly pdf: PdfService,
  ) {}

  @Post(':codigo/iniciar')
  async iniciar(@Param('codigo') codigo: string) {
    await this.db.query(
      `UPDATE ordenes SET iniciada_at = COALESCE(iniciada_at, now()) WHERE codigo = $1`,
      [codigo],
    );
    return { _idempotent: false };
  }

  @Post(':codigo/cerrar')
  async cerrar(
    @Param('codigo') codigo: string,
    @Body() body: any,
  ) {
    this.logger.log(`[EVID] ENTER cerrar codigo=${codigo} keys=${Object.keys(body||{}).join(',')}`);

    // Firma
    if (body?.firmaBase64?.startsWith('data:') && body.firmaBase64.includes(';base64,')) {
      const key = `firmas/${codigo}.png`;
      try {
        this.logger.log(`[EVID] put firma -> ${key}`);
        await this.pdf.putObject(key, body.firmaBase64, 'image/png', { 'Cache-Control':'public, max-age=600' });
        this.logger.log(`[EVID] OK firma -> ${key}`);
      } catch (e) {
        this.logger.warn(`[EVID] error firma ${key}: ${String((e as any)?.code || e)}`);
      }
    } else {
      this.logger.warn('[EVID] firma ausente o no es dataURL base64');
    }

    // Fotos
    if (Array.isArray(body?.evidenciasBase64)) {
      let i = 0;
      for (const dataUrl of body.evidenciasBase64) {
        i++;
        if (!(typeof dataUrl === 'string' && dataUrl.startsWith('data:') && dataUrl.includes(';base64,'))) {
          this.logger.warn(`[EVID] foto #${i} ignorada (no es dataURL base64)`);
          continue;
        }
        const key = `fotos/${codigo}/${i}.png`;
        try {
          this.logger.log(`[EVID] put foto -> ${key}`);
          await this.pdf.putObject(key, dataUrl, 'image/png', { 'Cache-Control':'public, max-age=600' });
          this.logger.log(`[EVID] OK foto -> ${key}`);
        } catch (e) {
          this.logger.warn(`[EVID] error foto #${i} ${key}: ${String((e as any)?.code || e)}`);
        }
      }
    } else {
      this.logger.warn('[EVID] evidenciasBase64 ausente o no es array');
    }

    await this.db.query(
      `UPDATE ordenes SET estado='cerrada', cerrada_at=now() WHERE codigo = $1`,
      [codigo],
    );

    return {
      codigo,
      estado: 'cerrada',
      cerradaAt: new Date().toISOString(),
      pdfUrl: null,
      _idempotent: false,
    };
  }
}
