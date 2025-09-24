import { Injectable, Logger } from '@nestjs/common';
import axios from 'axios';

@Injectable()
export class SmartoltService {
  private readonly logger = new Logger(SmartoltService.name);

  // Variables opcionales: si no están, trabajamos en modo MOCK.
  private readonly base = process.env.SMARTOLT_BASE_URL || '';
  private readonly token = process.env.SMARTOLT_TOKEN || '';

  /**
   * Activa ONU en SmartOLT (o MOCK si no hay credenciales).
   * Retorna { ok: true } cuando "activó" correctamente.
   */
  async activateOnu(serial: string, vlan: string): Promise<{ ok: boolean; data?: any; error?: string; mock?: boolean }> {
    if (!this.base || !this.token) {
      // Modo MOCK: simula éxito
      this.logger.log(`[MOCK] Activar ONU serial=${serial} vlan=${vlan}`);
      await new Promise((r) => setTimeout(r, 800));
      return { ok: true, mock: true };
    }

    try {
      const resp = await axios.post(
        `${this.base}/activate`,
        { serial, vlan },
        { headers: { 'X-Auth-Token': this.token } },
      );
      return { ok: true, data: resp.data };
    } catch (err: any) {
      const msg = err?.response?.data ? JSON.stringify(err.response.data) : (err?.message || 'SmartOLT error');
      this.logger.error(`SmartOLT error: ${msg}`);
      return { ok: false, error: msg };
    }
  }
}
