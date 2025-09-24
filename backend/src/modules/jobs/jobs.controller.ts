// src/modules/jobs/jobs.controller.ts
import { Controller, Post, Query, HttpCode } from '@nestjs/common';
import { JobsService } from './jobs.service';

@Controller('jobs')
export class JobsController {
  constructor(private readonly svc: JobsService) {}

  @Post('simular-cortes')
  @HttpCode(200)
  simularCortes(@Query('fecha') fecha?: string) {
    return this.svc.simular('COR', fecha);
  }

  @Post('simular-reconexiones')
  @HttpCode(200)
  simularRec(@Query('fecha') fecha?: string) {
    return this.svc.simular('REC', fecha);
  }
}
