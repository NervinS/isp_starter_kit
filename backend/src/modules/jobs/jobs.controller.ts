// src/modules/jobs/jobs.controller.ts
import { Controller, Post, Query, Body, HttpCode, Logger } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';

@ApiTags('Jobs')
@Controller('jobs') // el /v1 lo agrega el globalPrefix
export class JobsController {
  private readonly logger = new Logger(JobsController.name);

  /**
   * Simula cortes (versión safe en Fase 0/1).
   * Si dryRun=1 o JOBS_FAKE=1, hace no-op y responde 202.
   */
  @Post('simular-cortes')
  @HttpCode(202)
  @ApiOperation({ summary: 'Simular cortes (safe/dry-run disponible)' })
  async simularCortes(
    @Body() _body: any,
    @Query('dryRun') dryRun = '0',
  ) {
    const fake = process.env.JOBS_FAKE === '1' || dryRun === '1';
    if (fake) {
      this.logger.log('simular-cortes: dryRun/JOBS_FAKE activado → no-op');
      return { ok: true, dryRun: true, processed: 0 };
    }
    try {
      // TODO: aquí irá la lógica real en fases siguientes.
      this.logger.log('simular-cortes: placeholder (no-op)');
      return { ok: true, processed: 0 };
    } catch (e: any) {
      this.logger.error(`simular-cortes error: ${e?.message || e}`);
      // No reventamos el smoke: devolvemos OK lógico para Fase 0/1
      return { ok: true, fallback: true };
    }
  }

  /**
   * Simula reconexiones (versión safe en Fase 0/1).
   * Si dryRun=1 o JOBS_FAKE=1, hace no-op y responde 202.
   */
  @Post('simular-reconexiones')
  @HttpCode(202)
  @ApiOperation({ summary: 'Simular reconexiones (safe/dry-run disponible)' })
  async simularReconexiones(
    @Body() _body: any,
    @Query('dryRun') dryRun = '0',
  ) {
    const fake = process.env.JOBS_FAKE === '1' || dryRun === '1';
    if (fake) {
      this.logger.log('simular-reconexiones: dryRun/JOBS_FAKE activado → no-op');
      return { ok: true, dryRun: true, processed: 0 };
    }
    try {
      // TODO: lógica real en fases siguientes.
      this.logger.log('simular-reconexiones: placeholder (no-op)');
      return { ok: true, processed: 0 };
    } catch (e: any) {
      this.logger.error(`simular-reconexiones error: ${e?.message || e}`);
      return { ok: true, fallback: true };
    }
  }
}
