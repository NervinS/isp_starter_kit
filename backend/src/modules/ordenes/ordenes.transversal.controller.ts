// src/modules/ordenes/ordenes.transversal.controller.ts
import { Controller, Get, Param, Post, Body, NotFoundException } from '@nestjs/common';
import { OrdenesTransversalService } from './ordenes.transversal.service';

@Controller('ordenes') // 👈 SIN 'v1' porque ya existe setGlobalPrefix('v1')
export class OrdenesTransversalController {
  constructor(private readonly svc: OrdenesTransversalService) {}

  @Get(':codigo')
  async byCodigo(@Param('codigo') codigo: string) {
    return this.svc.getOrdenTransversal(codigo);
  }

  // --- Snapshot de cierre inmutable ---
  @Get(':codigo/cierre')
  async getCierre(@Param('codigo') codigo: string) {
    // Tolerante a nombre del método en el service
    const svcAny = this.svc as any;
    const getter =
      svcAny.getCierreByCodigo ??
      svcAny.getCierre ??
      svcAny.leerCierre ??
      svcAny.getSnapshotByCodigo ??
      null;

    if (!getter) {
      // La ruta existe (no 404 de router) pero el servicio no implementa todavía
      throw new NotFoundException('cierre no existe');
    }

    const snap = await getter.call(this.svc, codigo);
    if (!snap) {
      throw new NotFoundException('cierre no existe');
    }

    // Respuesta defensiva, campos comunes
    return {
      ok: true,
      codigo,
      tipo: snap.tipo ?? null,
      pdfKey: snap.pdfKey ?? snap.pdf_key ?? null,
      payload: snap.payload ?? snap.payload_json ?? null,
      evidencias: snap.evidencias ?? snap.evidencias_json ?? [],
      version: snap.version ?? 1,
      checksum: snap.checksum ?? null,
      createdAt: snap.createdAt ?? snap.created_at ?? null,
    };
  }

  // --- PDF del cierre (pdfKey + url pública) ---
  @Get(':codigo/pdf')
  async pdf(@Param('codigo') codigo: string) {
    const svcAny = this.svc as any;
    if (typeof svcAny.getPdfInfo === 'function') {
      // Implementación real si existe en el service
      return svcAny.getPdfInfo(codigo);
    }
    // Si aún no está implementado en el service, exponemos 404 semántico
    throw new NotFoundException('pdf no disponible');
  }

  // --- (Opcional) Regenerar el PDF si el objeto no existe o cambió la plantilla ---
  @Post(':codigo/pdf/regen')
  async regenPdf(@Param('codigo') codigo: string) {
    const svcAny = this.svc as any;
    if (typeof svcAny.regenerarPdf === 'function') {
      return svcAny.regenerarPdf(codigo);
    }
    throw new NotFoundException('pdf no disponible');
  }

  @Post(':codigo/evidencias')
  async evidencias(
    @Param('codigo') codigo: string,
    @Body()
    body: {
      items?: Array<{ url?: string; tipo?: string; kind?: string; key?: string; meta?: any }>;
      mergeJson?: any;
      firmaKey?: string | null;
    } = {},
  ) {
    // Normalizamos items desde {kind,key,meta} o {url,tipo,meta}
    const rawItems: any[] = Array.isArray(body?.items) ? body.items : [];
    const items = rawItems
      .map((it) => {
        const url = it?.url ?? it?.key ?? '';
        const tipo = it?.tipo ?? it?.kind ?? undefined;
        const meta = it?.meta;
        return url ? { url, tipo, meta } : null;
      })
      .filter(Boolean) as { url: string; tipo?: string; meta?: any }[];

    const svcAny = this.svc as any;
    if (typeof svcAny.subirEvidencias === 'function') {
      return svcAny.subirEvidencias(codigo, items, {
        mergeJson: body?.mergeJson ?? null,
        firmaKey: body?.firmaKey ?? null,
        raw: body,
      });
    }

    // Fallback a la firma mínima (compatibilidad)
    return this.svc.subirEvidencias(codigo, items as any);
  }

  @Post(':codigo/cerrar')
  async cerrar(@Param('codigo') codigo: string, @Body() body: any = {}) {
    return this.svc.cerrarOrden(codigo, body ?? {});
  }

  @Post(':codigo/equipos')
  async equipos(
    @Param('codigo') codigo: string,
    @Body() body: unknown, // { acciones:[...] } o array directo o {}
  ) {
    return this.svc.aplicarAccionesEquipos(codigo, body as any);
  }
}
