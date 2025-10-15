// src/modules/ventas/ventas.controller.ts
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { VentasService } from './ventas.service';

type EvidenciasBody = {
  cedula_key?: string | null;
  recibo_key?: string | null;
  firma_key?: string | null;

  // soporte opcional por si algún front manda base64
  cedula_base64?: string | null;
  recibo_base64?: string | null;
  firma_base64?: string | null;
};

@Controller('ventas') // Con GlobalPrefix('/v1') => /v1/ventas
export class VentasController {
  constructor(private readonly ventas: VentasService) {}

  // POST /v1/ventas
  @Post()
  async crear(@Body() body: any) {
    // Solo los campos que admite CrearVentaDto (+ mensual_total opcional)
    const { cliente_nombre, cliente_apellido, documento, plan, total } = body ?? {};
    if (!cliente_nombre || !cliente_apellido || !documento || !plan || total === undefined) {
      throw new BadRequestException(
        'Campos requeridos: cliente_nombre, cliente_apellido, documento, plan, total',
      );
    }
    const payload = {
      cliente_nombre: String(cliente_nombre),
      cliente_apellido: String(cliente_apellido),
      documento: String(documento),
      plan: String(plan),
      total,
      // opcional si lo provee el front:
      mensual_total:
        body?.mensual_total !== undefined && body?.mensual_total !== null
          ? body.mensual_total
          : null,
      // estos NO están en el DTO ni en tu tabla actual, por eso NO los pasamos:
      // alta_costo, mensual_internet, mensual_tv, incluye_tv, observaciones, etc.
    };
    return this.ventas.crearVenta(payload as any);
  }

  // GET /v1/ventas?estado=creada|pagada
  @Get()
  async listar(@Query('estado') estado?: string) {
    return this.ventas.listarVentas({ estado });
  }

  // GET /v1/ventas/:codigo
  @Get(':codigo')
  async detalle(@Param('codigo') codigo: string) {
    return this.ventas.detalleVenta(codigo);
  }

  // POST /v1/ventas/:codigo/evidencias
  @Post(':codigo/evidencias')
  async evidencias(@Param('codigo') codigo: string, @Body() body: EvidenciasBody) {
    return this.ventas.subirEvidencias(codigo, body);
  }

  // POST /v1/ventas/:codigo/asegurar-ins
  @Post(':codigo/asegurar-ins')
  async asegurarIns(@Param('codigo') codigo: string) {
    return this.ventas.asegurarIns(codigo);
  }

  // POST /v1/ventas/:codigo/pagar
  @Post(':codigo/pagar')
  async pagar(
    @Param('codigo') codigo: string,
    @Headers('idempotency-key') _idem?: string, // opcional; el service actual no lo requiere
  ) {
    return this.ventas.pagarVenta(codigo);
  }
}
