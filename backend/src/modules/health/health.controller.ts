// src/modules/health/health.controller.ts
import { Controller, Get } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Controller('health')
export class HealthController {
  constructor(private readonly ds: DataSource) {}

  @Get()
  async health() {
    const nowIso = new Date().toISOString();

    let dbOk = false;
    let dbTime: string | undefined;

    try {
      const rows = await this.ds.query(
        `SELECT to_char((now() at time zone 'UTC'),
                 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS "dbTime"`,
      );
      const raw = rows?.[0]?.dbTime;
      if (typeof raw === 'string' && raw.length > 0) {
        dbTime = raw;
        dbOk = true;
      }
    } catch {
      dbOk = false;
    }

    return {
      ok: true,
      ts: nowIso,
      dbOk,
      ...(dbTime ? { dbTime } : {}),
    };
  }
}
