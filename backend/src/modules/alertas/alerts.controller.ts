// src/modules/alertas/alerts.controller.ts
import { Controller, Get } from '@nestjs/common';
import { AlertsService } from './alerts.service';

@Controller('alertas') // con globalPrefix('v1') → /v1/alertas
export class AlertsController {
  constructor(private readonly alerts: AlertsService) {}

  @Get()
  async list() {
    return this.alerts.listActive();
  }
}
