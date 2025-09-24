import { Injectable, Logger } from '@nestjs/common';
import { SmartoltService } from './smartolt.service';

type ActivacionPayload = {
  ordenCodigo: string;
  serial: string;
  vlan: string;
};

@Injectable()
export class SmartoltQueue {
  private readonly logger = new Logger(SmartoltQueue.name);
  private busy = false;
  private q: ActivacionPayload[] = [];

  constructor(private readonly smartolt: SmartoltService) {}

  /**
   * Encola una activación. El procesamiento es interno y secuencial.
   */
  enqueueActivacion(p: ActivacionPayload) {
    this.q.push(p);
    this.logger.log(`Encolada activación: ${p.ordenCodigo} (${p.serial}/${p.vlan})`);
    void this.process();
  }

  private async process() {
    if (this.busy) return;
    this.busy = true;
    try {
      while (this.q.length) {
        const job = this.q.shift()!;
        this.logger.log(`Procesando activación ${job.ordenCodigo}...`);
        const r = await this.smartolt.activateOnu(job.serial, job.vlan);
        if (r.ok) this.logger.log(`SmartOLT OK (${job.ordenCodigo})${r.mock ? ' [MOCK]' : ''}`);
        else this.logger.error(`SmartOLT FALLÓ (${job.ordenCodigo}): ${r.error}`);
      }
    } finally {
      this.busy = false;
    }
  }
}
