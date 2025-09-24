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

  // estado: creada | pagada | ...
  @Column({ length: 20, default: 'creada' }) estado: string;

  // snapshot del plan en el momento de la venta
  @Column({ length: 20 })   plan_codigo: string;
  @Column({ length: 120 })  plan_nombre: string;
  @Column({ type: 'int', nullable: true }) plan_vel_mbps: number | null;

  // precios (numeric en PG -> string en TypeORM)
  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  alta_costo: string;

  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  mensual_internet: string;

  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  mensual_tv: string;

  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  mensual_total: string;

  @Column({ default: false }) incluye_tv: boolean;

  // total cobrado hoy (instalación)
  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  total: string;

  // PDFs en MinIO
  @Column({ nullable: true }) recibo_pdf_key: string | null;
  @Column({ nullable: true }) contrato_pdf_key: string | null;

  @Column({ type: 'timestamptz', default: () => 'now()' }) created_at: Date;
}
