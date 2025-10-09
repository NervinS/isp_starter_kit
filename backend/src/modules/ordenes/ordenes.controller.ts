// src/modules/ordenes/ordenes.controller.ts
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Headers,
  NotFoundException,
  Param,
  Post,
  Put,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Orden } from './orden.entity';

type CerrarBody = {
  comentarios?: string | null;
  materiales?: any[];
  equipos?: { asignar?: any[]; retirar?: any[] };
  pdfUrl?: string | null;
  pdfKey?: string | null;
};

function pick<T extends object, K extends readonly (keyof any)[]>(
  obj: T,
  keys: K,
): Partial<Record<K[number], any>> {
  return (keys as readonly string[]).reduce((acc, k) => {
    const v = (obj as any)[k];
    if (v !== undefined) (acc as any)[k] = v;
    return acc;
  }, {} as any);
}

function normalizeEvidenciasPayload(body: any) {
  const firmaKey = body?.firmaKey ?? body?.firma_key ?? null;

  const raw = {
    foto1Key: body?.foto1Key ?? body?.foto1_key,
    foto2Key: body?.foto2Key ?? body?.foto2_key,
    foto3Key: body?.foto3Key ?? body?.foto3_key,
  };

  const cleaned = Object.fromEntries(
    Object.entries(raw).filter(([, v]) => v !== undefined),
  );

  const providedEvidencias =
    typeof body?.evidencias === 'object' && body?.evidencias
      ? body.evidencias
      : {};

  return { firmaKey, evidenciasDelta: { ...providedEvidencias, ...cleaned } };
}

@Controller('ordenes') // el /v1 lo agrega el globalPrefix
export class OrdenesController {
  constructor(
    @InjectRepository(Orden)
    private readonly ordenRepo: Repository<Orden>,
  ) {}

  @Get()
  async list(): Promise<Orden[]> {
    return this.ordenRepo.find({ take: 50, order: { createdAt: 'DESC' } });
  }

  @Get(':codigo')
  async byCodigo(@Param('codigo') codigo: string): Promise<Orden> {
    const orden = await this.ordenRepo.findOne({ where: { codigo } });
    if (!orden) throw new NotFoundException('orden no existe');
    return orden;
  }

  @Put(':codigo/guardar')
  async guardar(@Param('codigo') codigo: string, @Body() body: any) {
    const orden = await this.ordenRepo.findOne({ where: { codigo } });
    if (!orden) throw new NotFoundException('orden no existe');

    const { firmaKey, evidenciasDelta } = normalizeEvidenciasPayload(body);
    const mergedEvidencias = { ...(orden.evidencias ?? {}), ...evidenciasDelta };

    const set: Partial<Orden> = { evidencias: mergedEvidencias };
    if (firmaKey !== null) set.firmaKey = firmaKey;

    await this.ordenRepo.update({ codigo }, set);
    const updated = await this.ordenRepo.findOne({ where: { codigo } });

    return {
      ok: true,
      codigo,
      firmaKey: updated?.firmaKey ?? null,
      evidencias: updated?.evidencias ?? null,
    };
  }

  @Post(':codigo/evidencias')
  async evidencias(@Param('codigo') codigo: string, @Body() body: any) {
    return this.guardar(codigo, body);
  }

  @Put(':codigo/cerrar')
  async cerrar(
    @Param('codigo') codigo: string,
    @Body() body: CerrarBody,
    @Headers('Idempotency-Key') idem?: string,
  ) {
    const orden = await this.ordenRepo.findOne({ where: { codigo } });
    if (!orden) throw new NotFoundException('orden no existe');

    if (orden.estado === 'anulada') {
      throw new BadRequestException('no se puede cerrar en estado=anulada');
    }
    if (orden.estado === 'cerrada') {
      return {
        _idempotent: true,
        ok: true,
        codigo,
        estado: orden.estado,
        cerradaAt: orden.cerradaAt,
      };
    }

    // Guardar payload de cierre en el jsonb correcto (payloadCierre)
    const payloadCierre = {
      comentarios: body?.comentarios ?? null,
      materiales: Array.isArray(body?.materiales) ? body!.materiales : [],
      equipos:
        typeof body?.equipos === 'object' && body?.equipos
          ? body!.equipos
          : { asignar: [], retirar: [] },
    };

    const set: Partial<Orden> = {
      estado: 'cerrada',
      cerradaAt: new Date(),
      payloadCierre,
      ...pick(body ?? {}, ['pdfUrl', 'pdfKey']),
    };

    await this.ordenRepo.update({ codigo }, set);
    const updated = await this.ordenRepo.findOne({ where: { codigo } });

    return {
      ok: true,
      ...(idem ? { _idempotent: false } : {}),
      codigo,
      estado: updated?.estado ?? 'cerrada',
      cerradaAt: updated?.cerradaAt ?? null,
    };
  }

  @Post(':codigo/cerrar')
  async cerrarPost(
    @Param('codigo') codigo: string,
    @Body() body: CerrarBody,
    @Headers('Idempotency-Key') idem?: string,
  ) {
    return this.cerrar(codigo, body, idem);
  }
}
