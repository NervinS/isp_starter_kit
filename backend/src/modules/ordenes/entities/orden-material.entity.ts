import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

@Entity({ name: 'orden_materiales' })
@Index('ux_orden_materiales_orden_mat', ['ordenId', 'materialId'], { unique: true })
export class OrdenMaterial {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index()
  @Column({ type: 'uuid', name: 'orden_id' })
  ordenId!: string;

  // columna legacy (uuid “externa”) — se mantiene para compatibilidad
  @Index()
  @Column({ type: 'uuid', name: 'material_id' })
  materialId!: string;

  // puente a materiales.id (INTEGER real)
  @Column({ type: 'int', name: 'material_id_int', nullable: true })
  materialIdInt!: number | null;

  @Column({ type: 'int', name: 'cantidad', default: 1 })
  cantidad!: number;

  @Column({ type: 'numeric', precision: 12, scale: 2, name: 'precio_unitario', default: 0 })
  precioUnitario!: string;

  @Column({ type: 'numeric', precision: 14, scale: 2, name: 'total_calculado', nullable: true })
  totalCalculado!: string | null;

  @Column({ type: 'boolean', name: 'descontado', default: false })
  descontado!: boolean;

  @CreateDateColumn({ type: 'timestamptz', name: 'created_at' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz', name: 'updated_at' })
  updatedAt!: Date;
}
