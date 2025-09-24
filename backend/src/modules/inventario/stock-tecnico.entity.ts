import { Entity, PrimaryGeneratedColumn, Column, ManyToOne, JoinColumn, Index } from 'typeorm';
import { Material } from '../materiales/material.entity';
import { Tecnico } from '../tecnicos/tecnico.entity';

@Entity('inv_tecnico')
@Index(['tecnicoId', 'materialId'], { unique: true })
export class StockTecnico {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ name: 'tecnico_id', type: 'uuid' })
  tecnicoId!: string;

  @Column({ name: 'material_id', type: 'int' })
  materialId!: number; // FK INTEGER

  @Column({ type: 'numeric', precision: 12, scale: 3, default: 0 })
  cantidad!: string; // numeric -> string

  @ManyToOne(() => Tecnico, { onDelete: 'CASCADE', eager: false })
  @JoinColumn({ name: 'tecnico_id' })
  tecnico?: Tecnico;

  @ManyToOne(() => Material, { onDelete: 'RESTRICT', eager: false })
  @JoinColumn({ name: 'material_id' })
  material?: Material; // eager: false para que NO seleccione columnas no deseadas
}
