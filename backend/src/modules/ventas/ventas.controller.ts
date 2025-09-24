import {
  BadRequestException,
  Controller,
  Post,
  Param,
  Body,
  Get,
  Query,
  UseInterceptors,
  UploadedFiles,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, FindOptionsWhere } from 'typeorm';

import { Venta } from './ventas.entity';
import { Usuario } from '../usuarios/usuario.entity';
import { Orden } from '../ordenes/entities/orden.entity';
import { Roles } from '../../common/decorators/roles.decorator';
import { Plan } from '../planes/plan.entity';
import { MinioService } from '../storage/minio.service';
import { PdfService } from '../pdf/pdf.service';

import { FileFieldsInterceptor } from '@nestjs/platform-express';
import * as multer from 'multer';
import {
  IsBoolean,
  IsOptional,
  IsString,
  Length,
} from 'class-validator';

const TV_MENSUAL = 30000; // COP

// ---------- DTOs ----------
class CrearVentaDto {
  @IsString() @Length(1, 120)
  cliente_nombre!: string;

  @IsString() @Length(1, 120)
  cliente_apellido!: string;

  @IsString() @Length(1, 64)
  documento!: string;

  @IsString() @Length(1, 32)
  plan_codigo!: string;

  @IsOptional() @IsBoolean()
  incluye_tv?: boolean;

  @IsOptional() @IsString()
  telefono?: string;

  @IsOptional() @IsString()
  correo?: string;

  @IsOptional()
  direccion?: any;

  @IsOptional() @IsString()
  observaciones?: string;

  @IsOptional()
  adjuntos?: any;
}

type PagarDto = {
  firma_base64?: string | null;
  recibo_base64?: string | null;
  cedula_base64?: string | null;
};

@Controller('ventas')
export class VentasController {
  constructor(
    @InjectRepository(Venta)   private readonly ventasRepo: Repository<Venta>,
    @InjectRepository(Usuario) private readonly usuariosRepo: Repository<Usuario>,
    @InjectRepository(Orden)   private readonly ordenesRepo: Repository<Orden>,
    @InjectRepository(Plan)    private readonly planesRepo: Repository<Plan>,
    private readonly minio: MinioService,
    private readonly pdf: PdfService,
  ) {}

  private require<T extends object>(obj: T, key: keyof T, label?: string) {
    const val = (obj as any)[key];
    if (val === undefined || val === null || (typeof val === 'string' && val.trim() === '')) {
      throw new BadRequestException(`Falta campo requerido: ${label ?? String(key)}`);
    }
  }

  private async nextCode(prefix: 'VEN' | 'CLI' | 'ORD', table: 'ventas' | 'usuarios' | 'ordenes') {
    const rows = await this.ventasRepo.query(
      `SELECT COALESCE(MAX(CAST(SUBSTRING(codigo FROM '\\d+$') AS INTEGER)), 0) + 1 AS next
         FROM ${table}
        WHERE codigo LIKE $1`,
      [`${prefix}-%`],
    );
    const next: number = Number(rows?.[0]?.next ?? 1);
    return `${prefix}-${String(next).padStart(6, '0')}`;
  }

  // ------- GET simple para UI -------
  @Get()
  @Roles('ventas')
  async listar(@Query('estado') estado?: string) {
    const where: FindOptionsWhere<Venta> = {};
    if (estado) (where as any).estado = estado;
    const list = await this.ventasRepo.find({
      where,
      order: { created_at: 'DESC' as any },
      select: ['codigo','estado','total','plan_nombre','plan_codigo','mensual_total'] as any
    });
    return list.map(v => ({
      codigo: v.codigo,
      total: Number(v.total || 0),
      plan: { codigo: v.plan_codigo, nombre: v.plan_nombre },
      mensual_total: Number(v.mensual_total || 0),
      estado: v.estado,
    }));
  }

  // ------- POST /v1/ventas -------
  @Post()
  @Roles('ventas')
  async crear(@Body() dto: CrearVentaDto) {
    this.require(dto, 'cliente_nombre');
    this.require(dto, 'cliente_apellido');
    this.require(dto, 'documento');
    this.require(dto, 'plan_codigo');

    const plan = await this.planesRepo.findOne({ where: { codigo: dto.plan_codigo, activo: true } });
    if (!plan) throw new BadRequestException('Plan inválido');

    const incluyeTv = !!dto.incluye_tv;

    // Usuario (por documento) o crear
    let usuario = await this.usuariosRepo.findOne({ where: { documento: dto.documento } });
    if (!usuario) {
      const cliCodigo = await this.nextCode('CLI', 'usuarios');
      usuario = this.usuariosRepo.create({
        codigo: cliCodigo,
        tipo_cliente: 'hogar',
        nombre: dto.cliente_nombre,
        apellido: dto.cliente_apellido,
        documento: dto.documento,
        estado: 'nuevo',
      });
      usuario = await this.usuariosRepo.save(usuario);
    }

    const venCodigo = await this.nextCode('VEN', 'ventas');

    const alta = Number(plan.alta_costo || 0);
    const mInt = Number(plan.mensual || 0);
    const mTv  = incluyeTv ? TV_MENSUAL : 0;
    const mTot = mInt + mTv;

    const venta = this.ventasRepo.create({
      codigo: venCodigo,
      cliente_nombre: dto.cliente_nombre,
      cliente_apellido: dto.cliente_apellido,
      documento: dto.documento,
      usuario_id: usuario.id,
      estado: 'creada',

      plan_codigo: plan.codigo,
      plan_nombre: plan.nombre,
      incluye_tv: incluyeTv,
      alta_costo: String(alta),
      mensual_internet: String(mInt),
      mensual_tv: String(mTv),
      mensual_total: String(mTot),

      total: String(alta),

      // guardamos extras si llegan (para poder mostrarlos en la orden)
      telefono: dto.telefono ?? null as any,
      correo: dto.correo ?? null as any,
      direccion_json: dto.direccion ?? null as any,
      observaciones: dto.observaciones ?? null as any,
    } as any);

    const saved = await this.ventasRepo.save(venta);

    return {
      ok: true,
      venta: {
        id: saved.id, codigo: saved.codigo, estado: saved.estado,
        total: Number(saved.total),
        plan: { codigo: plan.codigo, nombre: plan.nombre, mensual: mInt },
        incluye_tv: incluyeTv, mensual_total: mTot, alta_costo: alta,
      },
      usuario: { id: usuario.id, codigo: usuario.codigo, estado: usuario.estado },
    };
  }

  // ------- Evidencias de venta -------
  @Post(':codigo/evidencias')
  @Roles('ventas')
  @UseInterceptors(FileFieldsInterceptor(
    [
      { name: 'cedula', maxCount: 1 },
      { name: 'recibo', maxCount: 1 },
      { name: 'firma',  maxCount: 1 },
    ],
    { storage: multer.memoryStorage(), limits: { fileSize: 8 * 1024 * 1024 } }
  ))
  async subirEvidencias(
    @Param('codigo') codigo: string,
    @UploadedFiles() files: { cedula?: Express.Multer.File[]; recibo?: Express.Multer.File[]; firma?: Express.Multer.File[]; },
  ) {
    const venta = await this.ventasRepo.findOne({ where: { codigo } });
    if (!venta) throw new BadRequestException('Venta no existe');

    const prefix = `evidencias/ventas/${venta.codigo}`;

    const up = async (f: Express.Multer.File | undefined, name: 'cedula'|'recibo'|'firma') => {
      if (!f || !f.buffer) return;
      const ext = (f.mimetype?.includes('png') && 'png')
               || (f.mimetype?.includes('jpeg') && 'jpg')
               || (f.mimetype?.includes('webp') && 'webp')
               || 'bin';
      const key = `${prefix}/${name}.${ext}`;
      await this.minio.saveBuffer(f.buffer, key, f.mimetype || 'application/octet-stream');
      (venta as any)[`${name}_img_key`] = key;
    };

    await up(files?.cedula?.[0], 'cedula');
    await up(files?.recibo?.[0], 'recibo');
    await up(files?.firma?.[0],  'firma');

    await this.ventasRepo.save(venta);
    return { ok: true, keys: { cedula: (venta as any).cedula_img_key, recibo: (venta as any).recibo_img_key, firma: (venta as any).firma_img_key } };
  }

  // --- helpers para base64 en /pagar ---
  private parseDataUrl(dataUrl?: string | null): { buf: Buffer; mime: string; ext: string } | null {
    if (!dataUrl) return null;
    const m = dataUrl.match(/^data:([^;]+);base64,(.+)$/i);
    if (!m) return null;
    const mime = m[1];
    const b64 = m[2];
    const buf = Buffer.from(b64, 'base64');
    const ext = mime.includes('png') ? 'png'
            : mime.includes('jpeg') ? 'jpg'
            : mime.includes('webp') ? 'webp'
            : mime.includes('pdf') ? 'pdf'
            : 'bin';
    return { buf, mime, ext };
  }

  private async saveDataUrlIf(dataUrl: string | null | undefined, keyWithoutExt: string): Promise<string | undefined> {
    const p = this.parseDataUrl(dataUrl);
    if (!p) return undefined;
    const key = `${keyWithoutExt}.${p.ext}`;
    await this.minio.saveBuffer(p.buf, key, p.mime);
    return key;
  }

  // ------- POST /v1/ventas/:codigo/pagar -------
  @Post(':codigo/pagar')
  @Roles('ventas')
  async pagar(@Param('codigo') codigo: string, @Body() body: PagarDto) {
    const venta = await this.ventasRepo.findOne({ where: { codigo } });
    if (!venta) throw new BadRequestException('Venta no existe');

    const usuario = await this.usuariosRepo.findOne({ where: { id: venta.usuario_id } });
    if (!usuario) throw new BadRequestException('Usuario de la venta no existe');

    const prefix = `evidencias/ventas/${venta.codigo}`;

    // Evidencias base64 (si llegan ahora)
    const firmaKey = await this.saveDataUrlIf(body?.firma_base64 ?? null,  `${prefix}/firma`);
    const reciboKey= await this.saveDataUrlIf(body?.recibo_base64 ?? null, `${prefix}/recibo`);
    const cedulaKey= await this.saveDataUrlIf(body?.cedula_base64 ?? null, `${prefix}/cedula`);

    if (firmaKey)  (venta as any).firma_img_key  = firmaKey;
    if (reciboKey) (venta as any).recibo_img_key = reciboKey;
    if (cedulaKey) (venta as any).cedula_img_key = cedulaKey;

    // Marcar pagada
    const wasPagada = (venta.estado === 'pagada');
    if (!wasPagada) {
      (venta as any).estado = 'pagada';
      await this.ventasRepo.save(venta);
    }

    // Asegurar/crear orden de instalación
    let orden = await this.ordenesRepo.findOne({ where: { ventaId: (venta as any).id } });

    if (!orden) {
      const ordCodigo = await this.nextCode('ORD', 'ordenes');
      const now = new Date();

      // “Snapshot” del cliente para que el front siempre tenga datos
      const ctxCliente = {
        nombre:   venta.cliente_nombre,
        apellido: venta.cliente_apellido,
        documento:venta.documento,
        telefono: (venta as any).telefono ?? null,
        direccion:(venta as any).direccion_json ?? null,
      };

      orden = this.ordenesRepo.create({
        codigo: ordCodigo,
        estado: 'agendada',
        tipo: 'INSTALACION',
        // MUY IMPORTANTE: asignar ambos campos con los nombres del entity
        ventaId: (venta as any).id,
        usuarioId: (venta as any).usuario_id ?? null,
        agendadoPara: now,
        contexto: { cliente: ctxCliente },
      } as any);

      orden = await this.ordenesRepo.save(orden);
    }

    // PDFs opcional
    const pdfEnabled = String(process.env.PDF_ENABLED || '').toLowerCase() === 'true';
    if (pdfEnabled) {
      try {
        const fecha = new Date();
        const mensualInt = Number(venta.mensual_internet || 0);
        const mensualTv  = Number(venta.mensual_tv || 0);
        const mensualTot = Number(venta.mensual_total || 0);
        const alta       = Number(venta.alta_costo || 0);

        let firmaBuf: Buffer | null = null;
        if ((venta as any).firma_img_key) {
          try { firmaBuf = await this.minio.getBuffer((venta as any).firma_img_key); } catch {}
        }
        if (!firmaBuf && body?.firma_base64) {
          const p = this.parseDataUrl(body.firma_base64);
          if (p) firmaBuf = p.buf;
        }

        const reciboBuf = await this.pdf.reciboVenta({
          ventaCodigo: venta.codigo,
          cliente: `${usuario.nombre || ''} ${usuario.apellido || ''}`.trim(),
          documento: usuario.documento,
          planNombre: venta.plan_nombre || '',
          incluyeTv: !!venta.incluye_tv,
          altaCosto: alta,
          mensual: mensualInt,
          mensualTv,
          fecha,
        });

        const contratoBuf = await this.pdf.contrato({
          ventaCodigo: venta.codigo,
          cliente: `${usuario.nombre || ''} ${usuario.apellido || ''}`.trim(),
          documento: usuario.documento,
          planNombre: venta.plan_nombre || '',
          incluyeTv: !!venta.incluye_tv,
          mensualTotal: mensualTot,
          fecha,
          firmaPng: firmaBuf,
        });

        const reciboPdfKey   = `${prefix}/recibo.pdf`;
        const contratoPdfKey = `${prefix}/contrato.pdf`;

        await this.minio.saveBuffer(reciboBuf,   reciboPdfKey,   'application/pdf');
        await this.minio.saveBuffer(contratoBuf, contratoPdfKey, 'application/pdf');

        (venta as any).recibo_pdf_key   = reciboPdfKey;
        (venta as any).contrato_pdf_key = contratoPdfKey;
        await this.ventasRepo.save(venta);
      } catch (e) {
        console.warn('[ventas/pagar] No se pudo generar/subir PDFs:', e);
      }
    }

    const reciboUrl   = (venta as any).recibo_pdf_key   ? await this.minio.getSignedUrl((venta as any).recibo_pdf_key)   : null;
    const contratoUrl = (venta as any).contrato_pdf_key ? await this.minio.getSignedUrl((venta as any).contrato_pdf_key) : null;

    return {
      ok: true,
      venta: {
        codigo: venta.codigo,
        estado: venta.estado,
        recibo_url: reciboUrl,
        contrato_url: contratoUrl,
      },
      orden: orden
        ? {
            id: (orden as any).id,
            codigo: (orden as any).codigo,
            estado: (orden as any).estado,
            tipo: (orden as any).tipo,
            agendadoPara: (orden as any).agendadoPara ?? null,
          }
        : null,
    };
  }
}
