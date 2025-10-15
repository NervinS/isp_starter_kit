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
import { OrdenesService } from './ordenes.service';

type CerrarBody = {
  comentarios?: string | null;
  materiales?: any[];
  equipos?: { asignar?: any[]; retirar?: any[] };
  pdfUrl?: string | null; // compat anterior (no se usa en snapshot)
  pdfKey?: string | null; // clave PDF final (se guarda en orden_cierres)
  payload_cierre?: Record<string, any> | null; // para service.cerrarConSnapshot
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

@Controller('ordenes') // /v1 lo agrega el globalPrefix
export class OrdenesController {
  constructor(
    @InjectRepository(Orden)
    private readonly ordenRepo: Repository<Orden>,
    private readonly ordenesService: OrdenesService,
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

  /**
   * Guardado incremental legacy (merge JSON en ordenes.evidencias / firmaKey).
   * Se mantiene por compatibilidad.
   */
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

  /**
   * NUEVO: Evidencias ricas
   * Inserta en orden_evidencias y opcionalmente mergea JSON legacy + firmaKey.
   * Body:
   * {
   *   items: [{kind, key, meta?}, ...],      // requerido para tabla rica
   *   mergeJson?: {...},                      // opcional (legacy)
   *   firmaKey?: "evidencias/.../firma.png"   // opcional (legacy)
   * }
   */
  @Post(':codigo/evidencias')
  async evidenciasRich(@Param('codigo') codigo: string, @Body() body: any) {
    const items = Array.isArray(body?.items) ? body.items : [];
    const mergeJson = (typeof body?.mergeJson === 'object' && body.mergeJson) ? body.mergeJson : null;
    const firmaKey = body?.firmaKey ?? null;

    const res = await this.ordenesService.addEvidenciasRich(codigo, { items, mergeJson, firmaKey });
    return res;
  }

  /**
   * Cierre con snapshot inmutable.
   * Guarda orden_cierres (idempotente) y marca orden como cerrada.
   */
  @Put(':codigo/cerrar')
  async cerrar(
    @Param('codigo') codigo: string,
    @Body() body: CerrarBody,
    @Headers('Idempotency-Key') idem?: string,
  ) {
    const payload_cierre =
      body?.payload_cierre ??
      {
        comentarios: body?.comentarios ?? null,
        materiales: Array.isArray(body?.materiales) ? body.materiales : [],
        equipos:
          typeof body?.equipos === 'object' && body?.equipos
            ? body.equipos
            : { asignar: [], retirar: [] },
      };

    return this.ordenesService.cerrarConSnapshot(codigo, {
      payload_cierre,
      pdfKey: body?.pdfKey ?? null,
      idemKey: idem ?? null,
    });
  }

  @Post(':codigo/cerrar')
  async cerrarPost(
    @Param('codigo') codigo: string,
    @Body() body: CerrarBody,
    @Headers('Idempotency-Key') idem?: string,
  ) {
    return this.cerrar(codigo, body, idem);
  }

  /** Lee el snapshot inmutable de cierre (orden_cierres) */
  @Get(':codigo/cierre')
  async getCierre(@Param('codigo') codigo: string) {
    const snap = await this.ordenesService.getCierre(codigo);
    if (!snap) throw new NotFoundException('snapshot de cierre no existe');
    return snap;
  }
}
