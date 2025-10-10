// src/modules/ventas/ventas.entity.ts
import { Entity, PrimaryGeneratedColumn, Column } from 'typeorm';

@Entity({ name: 'ventas' })
export class Venta {
  // PK UUID (generada por la DB)
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  // Código externo/legible de la venta
  @Column({ type: 'varchar', length: 20 })
  codigo!: string;

  // Datos del cliente
  @Column({ type: 'varchar', length: 120 })
  cliente_nombre!: string;

  @Column({ type: 'varchar', length: 120 })
  cliente_apellido!: string;

  @Column({ type: 'varchar', length: 30 })
  documento!: string;

  // Referencia al usuario (FK lógica)
  @Column({ type: 'uuid' })
  usuario_id!: string;

  // Estado: creada | pagada | anulada
  @Column({ type: 'varchar', length: 20, default: 'creada' })
  estado!: string;

  // Plan textual (si luego normalizas, cambia a FK)
  @Column({ type: 'varchar', length: 120 })
  plan!: string;

  // Totales: usar string en TS para evitar pérdidas con DECIMAL
  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  mensual_total!: string;

  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  total!: string;

  // Ubicaciones de PDFs en MinIO (opcionales)
  @Column({ type: 'varchar', nullable: true })
  recibo_pdf_key!: string | null;

  @Column({ type: 'varchar', nullable: true })
  contrato_pdf_key!: string | null;

  // Marca de creación
  @Column({ type: 'timestamptz', default: () => 'now()' })
  created_at!: Date;
}
