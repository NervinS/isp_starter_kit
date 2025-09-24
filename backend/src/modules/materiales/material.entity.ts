import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  Index,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';

@Entity({ name: 'materiales' })
@Index('ux_materiales_codigo', ['codigo'], { unique: true })
export class Material {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'text' })
  codigo: string;

  @Column({ type: 'text', unique: true })
  nombre: string;

  // PG numeric -> TypeORM devuelve string; guardamos como string para evitar pérdida de precisión
  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  precio: string;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz', default: () => 'now()' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz', default: () => 'now()' })
  updatedAt: Date;

  // ⚠️ Importante: NO hay columnas 'unidad' ni 'activo' en DB, por eso no las declaramos aquí.
}
