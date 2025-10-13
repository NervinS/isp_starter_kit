// src/modules/ordenes/ordenes.transversal.service.ts
import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Orden } from './entities/orden.entity';

type OrdenTransversalDTO = {
  codigo: string;
  estado: string;
  tipo: string;
  agendadoPara: string | null; // ISO para respuesta
  turno: string | null;
  cerradaAt: string | null;    // ISO
  tecnicoId: number | null;
  usuarioId: string | null;
  ventaId: string | null;
  createdAt: string;           // ISO
  updatedAt: string;           // ISO
};

@Injectable()
export class OrdenesTransversalService {
  constructor(
    @InjectRepository(Orden)
    private readonly ordenRepo: Repository<Orden>,
  ) {}

  // ========= GET /ordenes/:codigo =========
  async getOrdenTransversal(codigo: string): Promise<OrdenTransversalDTO> {
    const orden = await this.ordenRepo.findOne({
      where: { codigo },
      select: {
        codigo: true,
        estado: true,
        tipo: true,
        agendadoPara: true,
        turno: true,
        cerradaAt: true,
        tecnicoId: true,
        usuarioId: true,
        ventaId: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!orden) {
      throw new NotFoundException(`Orden ${codigo} no encontrada`);
    }

    const toIso = (d: Date | null) => (d ? d.toISOString() : null);

    return {
      codigo: orden.codigo,
      estado: orden.estado,
      tipo: orden.tipo,
      agendadoPara: toIso(orden.agendadoPara),
      turno: orden.turno,
      cerradaAt: toIso(orden.cerradaAt),
      tecnicoId: orden.tecnicoId,
      usuarioId: orden.usuarioId,
      ventaId: orden.ventaId,
      createdAt: orden.createdAt.toISOString(),
      updatedAt: orden.updatedAt.toISOString(),
    };
  }

  // ========= POST /ordenes/:codigo/evidencias =========
  async subirEvidencias(
    codigo: string,
    items: Array<{ url: string; tipo?: string }> = [],
  ) {
    const orden = await this.ordenRepo.findOne({ where: { codigo } });
    if (!orden) throw new NotFoundException(`Orden ${codigo} no encontrada`);

    // Normalizamos y validamos superficialmente
    const saneados = (Array.isArray(items) ? items : []).filter(
      (it) => it && typeof it.url === 'string' && it.url.length > 0,
    );

    // Guardamos en jsonb (sobrescribimos simple; para append podrías leer/concatenar)
    await this.ordenRepo.update(
      { codigo },
      {
        evidencias: { items: saneados },
        updatedAt: () => 'now()',
      } as any,
    );

    return { ok: true, codigo, items: saneados.length };
  }

  // ========= POST /ordenes/:codigo/equipos =========
  // Acepta: {}, { acciones: [...] } o un array directo [...]
  async aplicarAccionesEquipos(codigo: string, body: unknown) {
    const orden = await this.ordenRepo.findOne({ where: { codigo } });
    if (!orden) throw new NotFoundException(`Orden ${codigo} no encontrada`);

    let acciones: any[] = [];

    if (Array.isArray(body)) {
      acciones = body;
    } else if (body && typeof body === 'object' && 'acciones' in (body as any)) {
      const maybe = (body as any).acciones;
      if (Array.isArray(maybe)) acciones = maybe;
    } else if (body == null || (typeof body === 'object' && Object.keys(body as any).length === 0)) {
      acciones = []; // cuerpo vacío -> no-op válido
    } else {
      // Cualquier otro formato lo consideramos inválido
      throw new BadRequestException('Formato inválido para acciones');
    }

    // En esta fase solo respondemos OK y (opcional) podríamos loggear/adjuntar al payload_abierto.
    // No toca inventario aquí. Deja un rastro simple:
    const prev = (orden.payloadAbierto as any) ?? {};
    await this.ordenRepo.update(
      { codigo },
      {
        payloadAbierto: {
          ...prev,
          equipos: { acciones, at: new Date().toISOString() },
        },
        updatedAt: () => 'now()',
      } as any,
    );

    return { ok: true, codigo, acciones: acciones.length };
  }

  // ========= POST /ordenes/:codigo/cerrar =========
  // Idempotente: si ya está cerrada, devuelve la misma foto (estado/cerradaAt).
  async cerrarOrden(
    codigo: string,
    payload: Partial<{ observaciones: string; pdfUrl: string; extra?: any }> = {},
  ) {
    const orden = await this.ordenRepo.findOne({
      where: { codigo },
      select: {
        id: true,
        codigo: true,
        estado: true,
        cerradaAt: true,
        payloadCierre: true,
        pdfUrl: true,
        updatedAt: true,
      },
    });

    if (!orden) throw new NotFoundException(`Orden ${codigo} no encontrada`);

    // Si ya está cerrada, retona lo mismo (idempotente)
    if (orden.cerradaAt) {
      return {
        ok: true,
        codigo: orden.codigo,
        estado: 'cerrada',
        cerradaAt: orden.cerradaAt.toISOString(),
      };
    }

    const now = new Date();
    const cierrePayload = {
      ...(orden.payloadCierre as any),
      ...payload,
      at: now.toISOString(),
    };

    await this.ordenRepo.update(
      { codigo },
      {
        estado: 'cerrada',
        cerradaAt: now,
        updatedAt: now,
        payloadCierre: cierrePayload,
        pdfUrl: payload.pdfUrl ?? (orden as any).pdfUrl ?? null,
      } as any,
    );

    return {
      ok: true,
      codigo,
      estado: 'cerrada',
      cerradaAt: now.toISOString(),
    };
  }
}
