// src/modules/tecnicos/tecnicos.service.ts
import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
  ConflictException,
} from '@nestjs/common';
import { DataSource } from 'typeorm';

type CierreMaterial =
  | { materialIdInt: number; cantidad: number }
  | { materialId: string; cantidad: number };

@Injectable()
export class TecnicosService {
  constructor(private readonly ds: DataSource) {}

  // --- Helpers --------------------------------------------------------------

  private async resolveMaterialIdInt(
    qr: import('typeorm').QueryRunner,
    mat: CierreMaterial,
  ): Promise<{ material_id_int: number; cantidad: number }> {
    const cantidad = (mat as any).cantidad ?? 0;
    if (cantidad <= 0) {
      throw new BadRequestException('Cantidad inválida');
    }

    // Caso A: ya viene como entero (camino feliz actual)
    if ('materialIdInt' in mat && Number.isInteger(mat.materialIdInt)) {
      return { material_id_int: mat.materialIdInt, cantidad };
    }

    // Caso B: viene un "materialId" alternativo -> lo resolvemos al entero (materiales.id)
    if ('materialId' in mat && mat.materialId) {
      const row = await qr.query(
        `SELECT id FROM materiales WHERE CAST(id AS text)=$1 OR codigo=$1 LIMIT 1`,
        [mat.materialId],
      );
      if (!row?.length) {
        throw new BadRequestException(`Material no existe: ${mat.materialId}`);
      }
      return { material_id_int: Number(row[0].id), cantidad };
    }

    throw new BadRequestException('Material sin identificador');
  }

  private ensureAsignadaAlTecnico(orden: any, tecnicoId: string) {
    if (!orden) throw new NotFoundException('Orden no existe');
    if (!orden.tecnico_id || orden.tecnico_id !== tecnicoId) {
      throw new ForbiddenException('Orden no asignada a este técnico');
    }
  }

  // --- Consultas ------------------------------------------------------------

  async pendientes(tecnicoId: string) {
    return this.ds.query(
      `
      SELECT *
      FROM ordenes
      WHERE tecnico_id = $1
        AND estado IN ('agendada','en_progreso')
      ORDER BY
        CASE WHEN estado='en_progreso' THEN 0 ELSE 1 END,
        agendado_para NULLS LAST,
        created_at DESC
      `,
      [tecnicoId],
    );
  }

  // --- Iniciar por CÓDIGO ---------------------------------------------------

  async iniciarPorCodigo(tecnicoId: string, codigo: string) {
    return this.ds.transaction(async (qr) => {
      const rows = await qr.query(
        `SELECT * FROM ordenes WHERE codigo=$1 FOR UPDATE`,
        [codigo],
      );
      const ord = rows[0];
      this.ensureAsignadaAlTecnico(ord, tecnicoId);

      if (ord.estado === 'en_progreso') {
        return {
          codigo: ord.codigo,
          estado: ord.estado,
          iniciada_at: ord.iniciada_at,
          cerrada_at: ord.cerrada_at,
          _idempotent: true,
        };
      }

      if (!['agendada', 'creada'].includes(ord.estado)) {
        throw new ConflictException(
          `No se puede iniciar desde estado ${ord.estado}`,
        );
      }

      const now = new Date().toISOString();
      await qr.query(
        `UPDATE ordenes SET estado='en_progreso', iniciada_at=$2, updated_at=$2 WHERE id=$1`,
        [ord.id, now],
      );

      const after = (
        await qr.query(
          `SELECT codigo, estado, iniciada_at, cerrada_at FROM ordenes WHERE id=$1`,
          [ord.id],
        )
      )[0];

      return {
        codigo: after.codigo,
        estado: after.estado,
        iniciada_at: after.iniciada_at,
        cerrada_at: after.cerrada_at,
        _idempotent: false,
      };
    });
  }

  // --- Cerrar por CÓDIGO ----------------------------------------------------

  /**
   * Cierre por técnico admitiendo materiales en dos formatos:
   *  - { materialIdInt, cantidad }  ← actual y más eficiente
   *  - { materialId, cantidad }     ← compatibilidad (se resuelve a id entero)
   *
   * Reglas de negocio delegadas:
   *  - MAN no afecta usuario
   *  - REC conecta usuario
   *  - Idempotencia: si la orden ya está cerrada, responde _idempotent: true
   *
   * Descuento de inventario:
   *  - Solo descuenta una vez por material/orden (usa ux_om_orden_mat_int)
   *  - Si no hay stock suficiente → 400
   */
  async cerrarPorCodigo(
    tecnicoId: string,
    codigo: string,
    body: { materiales?: CierreMaterial[] } = {},
  ) {
    return this.ds.transaction(async (qr) => {
      // 1) Lock de la orden y validaciones
      const rows = await qr.query(
        `SELECT * FROM ordenes WHERE codigo=$1 FOR UPDATE`,
        [codigo],
      );
      const ord = rows[0];
      this.ensureAsignadaAlTecnico(ord, tecnicoId);

      if (ord.estado === 'cerrada') {
        // Ya estaba cerrada: idempotente
        return {
          codigo: ord.codigo,
          estado: ord.estado,
          cerradaAt: ord.cerrada_at,
          pdfUrl: ord.pdf_url ?? null,
          _idempotent: true,
        };
      }
      if (ord.estado !== 'en_progreso') {
        throw new ConflictException(
          `No se puede cerrar desde estado ${ord.estado}`,
        );
      }

      // 2) Normalizar materiales a material_id_int
      const insumos: { material_id_int: number; cantidad: number }[] = [];
      for (const m of body.materiales ?? []) {
        insumos.push(await this.resolveMaterialIdInt(qr, m));
      }

      // 3) Descontar inventario (una sola vez por material/orden)
      //    y registrar líneas en orden_materiales con UNIQUE (orden_id, material_id_int)
      for (const { material_id_int, cantidad } of insumos) {
        // Si ya existe línea para este material (idempotencia por material)
        const existe = await qr.query(
          `SELECT 1
             FROM orden_materiales
            WHERE orden_id=$1 AND material_id_int=$2
            LIMIT 1`,
          [ord.id, material_id_int],
        );
        if (!existe?.length) {
          // Verificar stock suficiente
          const stok = await qr.query(
            `SELECT cantidad
               FROM inv_tecnico
              WHERE tecnico_id=$1 AND material_id=$2
              FOR UPDATE`,
            [tecnicoId, material_id_int],
          );

          const actual = Number(stok?.[0]?.cantidad ?? 0);
          if (actual < cantidad) {
            throw new BadRequestException('Stock insuficiente');
          }

          // Descontar
          await qr.query(
            `UPDATE inv_tecnico
                SET cantidad = cantidad - $3
              WHERE tecnico_id=$1 AND material_id=$2`,
            [tecnicoId, material_id_int, cantidad],
          );

          // Registrar línea
          await qr.query(
            `INSERT INTO orden_materiales
               (orden_id, material_id_int, cantidad, precio_unitario, total_calculado, descontado)
             VALUES ($1, $2, $3, 0, 0, true)`,
            [ord.id, material_id_int, cantidad],
          );
        }
      }

      // 4) Cerrar orden (aplica reglas de negocio MAN/REC y PDF)
      //    Implementamos el cierre aquí, alineado con tu comportamiento actual.
      const now = new Date().toISOString();
      await qr.query(
        `UPDATE ordenes
            SET estado='cerrada', cerrada_at=$2, updated_at=$2
          WHERE id=$1`,
        [ord.id, now],
      );

      // Reglas de usuario:
      if (ord.tipo === 'REC' && ord.usuario_id) {
        await qr.query(
          `UPDATE usuarios
              SET estado_conexion='conectado', updated_at=$2
            WHERE id=$1`,
          [ord.usuario_id, now],
        );
      }
      // MAN: no toca usuario

      // 5) PDF opcional: si ya tienes un job que lo sube a MinIO, puedes sustituir.
      // Dejamos url si ya existía (no forzamos a generar aquí).
      const after = (
        await qr.query(
          `SELECT codigo, estado, cerrada_at, pdf_url
             FROM ordenes
            WHERE id=$1`,
          [ord.id],
        )
      )[0];

      return {
        codigo: after.codigo,
        estado: after.estado,
        cerradaAt: after.cerrada_at,
        pdfUrl: after.pdf_url ?? null,
        _idempotent: false,
      };
    });
  }
}
