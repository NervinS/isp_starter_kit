import { Entity, PrimaryGeneratedColumn, Column, Index } from 'typeorm';

@Entity('orden_materiales')
export class OrdenMaterial {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index()
  @Column({ name: 'orden_id', type: 'uuid' })
  ordenId!: string;

  @Index()
  @Column({ name: 'material_id', type: 'uuid' })
  materialId!: string;

  @Column({ type: 'int', default: 1 })
  cantidad!: number;
}
