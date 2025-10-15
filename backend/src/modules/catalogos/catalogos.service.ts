// src/modules/catalogos/catalogos.service.ts
import { Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { CreateCatalogoItemDto, UpdateCatalogoItemDto } from './dto/catalogo-item.dto';

@Injectable()
export class CatalogosService {
  constructor(private readonly dataSource: DataSource) {}

  // ------------------------------------------------------------
  // MUNICIPIOS / VÍAS (público)
  // Acepta { q, activos } o (q, activos) para compatibilidad
  // ------------------------------------------------------------

  async listarMunicipios(
    arg?: { q?: string; activos?: boolean } | string,
    activosMaybe?: boolean,
  ) {
    const q =
      typeof arg === 'string' || typeof arg === 'undefined'
        ? arg
        : arg?.q;
    const activos =
      typeof arg === 'string' || typeof arg === 'undefined'
        ? activosMaybe
        : arg?.activos;

    const qParam = q?.trim() ? q.trim() : null;
    const activosParam = typeof activos === 'boolean' ? activos : null;

    const sql = `
      SELECT codigo, nombre, activo
        FROM public.municipios
       WHERE ($1::text IS NULL
              OR nombre ILIKE '%' || $1 || '%'
              OR codigo ILIKE '%' || $1 || '%')
         AND ($2::bool IS NULL OR activo = $2)
       ORDER BY codigo ASC
       LIMIT 200
    `;
    return this.dataSource.query(sql, [qParam, activosParam]);
  }

  async listarVias(
    arg?: { q?: string; activos?: boolean } | string,
    activosMaybe?: boolean,
  ) {
    const q =
      typeof arg === 'string' || typeof arg === 'undefined'
        ? arg
        : arg?.q;
    const activos =
      typeof arg === 'string' || typeof arg === 'undefined'
        ? activosMaybe
        : arg?.activos;

    const qParam = q?.trim() ? q.trim() : null;
    const activosParam = typeof activos === 'boolean' ? activos : null;

    const sql = `
      SELECT codigo, nombre, activo
        FROM public.vias
       WHERE ($1::text IS NULL
              OR nombre ILIKE '%' || $1 || '%'
              OR codigo ILIKE '%' || $1 || '%')
         AND ($2::bool IS NULL OR activo = $2)
       ORDER BY codigo ASC
       LIMIT 200
    `;
    return this.dataSource.query(sql, [qParam, activosParam]);
  }

  // ------------------------------------------------------------
  // MOTIVOS DE REAGENDA (admin + público)
  // ------------------------------------------------------------

  /** Público: lista motivos (opcional solo activos) */
  async motivosReagendaListarPublico(onlyActive = false) {
    const sql = `
      SELECT id, codigo, nombre, activo, orden
        FROM catalogo_motivos_reagenda
       WHERE ($1::boolean IS NOT TRUE OR activo = TRUE)
       ORDER BY orden NULLS LAST, nombre ASC
    `;
    return this.dataSource.query(sql, [onlyActive]);
  }

  /** Admin: lista completa */
  async motivosReagendaListarAdmin() {
    const sql = `
      SELECT id, codigo, nombre, activo, orden, created_at, updated_at
        FROM catalogo_motivos_reagenda
       ORDER BY orden NULLS LAST, nombre ASC
    `;
    return this.dataSource.query(sql, []);
  }

  /**
   * Admin: crear
   * Blindado: generamos 'codigo' explícitamente con la secuencia
   * para no depender del DEFAULT de la tabla (evita el 500 por null).
   */
  async crearMotivoReagenda(dto: CreateCatalogoItemDto) {
    const sql = `
      INSERT INTO motivos_reagenda (codigo, nombre, activo, orden)
      VALUES (
        ('MOT-' || LPAD(nextval('motivos_reagenda_codigo_seq')::TEXT, 6, '0')),
        $1,
        COALESCE($2, TRUE),
        COALESCE($3, 100)
      )
      RETURNING id, codigo, nombre, activo, orden, created_at, updated_at
    `;
    const params = [dto.nombre, dto.activo ?? null, dto.orden ?? null];
    const rows = await this.dataSource.query(sql, params);
    return rows[0];
  }

  /** Admin: actualizar por id (INTEGER) */
  async updateMotivoReagenda(id: number, dto: UpdateCatalogoItemDto) {
    const sql = `
      UPDATE motivos_reagenda
         SET nombre     = COALESCE($2, nombre),
             activo     = COALESCE($3, activo),
             orden      = COALESCE($4, orden),
             updated_at = now()
       WHERE id = $1
   RETURNING id, codigo, nombre, activo, orden, created_at, updated_at
    `;
    const params = [id, dto.nombre ?? null, dto.activo ?? null, dto.orden ?? null];
    const rows = await this.dataSource.query(sql, params);
    return rows[0] ?? null;
  }

  /** Admin: eliminar por id (INTEGER) */
  async deleteMotivoReagenda(id: number) {
    const sql = `
      DELETE FROM motivos_reagenda
       WHERE id = $1
   RETURNING id, codigo, nombre, activo, orden, created_at, updated_at
    `;
    const rows = await this.dataSource.query(sql, [id]);
    return rows[0] ?? null;
  }
}
