// backend/src/modules/inventario/entities/stock-tecnico.entity.ts
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  Unique,
  Index,
} from 'typeorm';
import { Tecnico } from '../../tecnicos/tecnico.entity';
import { Material } from '../../materiales/material.entity';

/**
 * Tabla: inv_tecnico
 * Columnas: id, tecnico_id, material_id, cantidad
 * NOTA: No agregamos created_at/updated_at porque no existen en tu tabla.
 */
@Entity('inv_tecnico')
@Unique('inv_tecnico_tecnico_id_material_id_key', ['tecnicoId', 'materialId'])
export class StockTecnico {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index('ix_inv_tecnico_tecnico')
  @Column({ name: 'tecnico_id', type: 'uuid' })
  tecnicoId: string;

  @ManyToOne(() => Tecnico, { eager: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'tecnico_id' })
  tecnico: Tecnico;

  @Index('ix_inv_tecnico_material')
  @Column({ name: 'material_id', type: 'uuid' })
  materialId: string;

  @ManyToOne(() => Material, { eager: true, onDelete: 'RESTRICT' })
  @JoinColumn({ name: 'material_id' })
  material: Material;

  @Column({ type: 'numeric', precision: 14, scale: 3, default: 0 })
  cantidad: string; // usar string para no perder precisión
}
