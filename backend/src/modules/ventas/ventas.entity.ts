// src/modules/ventas/ventas.entity.ts
import { Entity, PrimaryGeneratedColumn, Column } from 'typeorm';

@Entity({ name: 'ventas' })
export class Venta {
  @PrimaryGeneratedColumn('uuid') id: string;
  @Column({ length: 20 }) codigo: string;

  // cliente
  @Column({ length: 120 }) cliente_nombre: string;
  @Column({ length: 120 }) cliente_apellido: string;
  @Column({ length: 30 })  documento: string;
  @Column({ type: 'uuid' }) usuario_id: string;

  // estado: creada | pagada | anulada
  @Column({ length: 20, default: 'creada' }) estado: string;

  // Plan textual por ahora (puedes normalizar a planes.plan_codigo)
  @Column({ length: 120 }) plan: string;

  // totales
  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  mensual_total: string;

  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  total: string;

  // PDFs en MinIO
  @Column({ nullable: true }) recibo_pdf_key: string | null;
  @Column({ nullable: true }) contrato_pdf_key: string | null;

  @Column({ type: 'timestamptz', default: () => 'now()' }) created_at: Date;
}
