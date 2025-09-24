// src/modules/ordenes/services/idempotencia.service.ts
import { Injectable } from '@nestjs/common';
import { Repository } from 'typeorm';
import { InjectRepository } from '@nestjs/typeorm';
import { OrdenCierreIdem } from '../entities/orden-cierre-idem.entity';
import { payloadHash } from '../../../common/utils/payload-hash';

export type IdemRecord = {
  orden_codigo: string;
  payload_hash: string;
  idempotency_key?: string | null;
  response_status?: number | null;
  response_body?: any | null;
};

@Injectable()
export class IdempotenciaService {
  constructor(
    @InjectRepository(OrdenCierreIdem)
    private readonly repo: Repository<OrdenCierreIdem>,
  ) {}

  computeHash(payload: any): string {
    return payloadHash(payload);
  }

  async upsertFirstOrGet(params: {
    orden_codigo: string;
    payload: any;
    idempotency_key?: string | null;
  }): Promise<{ isFirst: boolean; record: OrdenCierreIdem }> {
    const hash = this.computeHash(params.payload);
    const existing = await this.repo.findOne({
      where: { orden_codigo: params.orden_codigo, payload_hash: hash },
    });
    if (existing) return { isFirst: false, record: existing };

    const rec = this.repo.create({
      orden_codigo: params.orden_codigo,
      payload_hash: hash,
      idempotency_key: params.idempotency_key ?? null,
    });
    const saved = await this.repo.save(rec);
    return { isFirst: true, record: saved };
  }

  async storeResponse(id: number, status: number, body: any): Promise<void> {
    await this.repo.update({ id }, { response_status: status, response_body: body });
  }
}
