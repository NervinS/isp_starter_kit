// backend/src/modules/ventas/ventas.entity.ts
import { Entity, PrimaryGeneratedColumn, Column } from 'typeorm';

@Entity({ name: 'ventas' })
export class Venta {
  // PK
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  // Código de la venta (ej. "VTA-0001")
  @Column({ type: 'varchar', length: 20 })
  codigo!: string;

  // Datos del cliente
  @Column({ type: 'varchar', length: 120 })
  cliente_nombre!: string;

  @Column({ type: 'varchar', length: 120 })
  cliente_apellido!: string;

  @Column({ type: 'varchar', length: 30 })
  documento!: string;

  // Relación/foránea hacia usuario (por ahora como UUID plano)
  @Column({ type: 'uuid' })
  usuario_id!: string;

  // Estado: creada | pagada | anulada
  @Column({ type: 'varchar', length: 20, default: 'creada' })
  estado!: string;

  // Plan textual (si luego normalizas, cámbialo a FK)
  @Column({ type: 'varchar', length: 120 })
  plan!: string;

  // Totales
  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  mensual_total!: string; // TypeORM devuelve numeric como string

  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  total!: string; // idem

  // Ubicaciones en MinIO de PDFs generados
  @Column({ type: 'varchar', length: 255, nullable: true })
  recibo_pdf_key!: string | null;

  @Column({ type: 'varchar', length: 255, nullable: true })
  contrato_pdf_key!: string | null;

  // Timestamps
  @Column({ type: 'timestamptz', default: () => 'now()' })
  created_at!: Date;
}
