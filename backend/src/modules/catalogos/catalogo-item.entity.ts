import { Column, CreateDateColumn, Entity, Index, JoinColumn, ManyToOne, PrimaryGeneratedColumn, UpdateDateColumn } from 'typeorm';
import { Catalogo } from './catalogo.entity';

@Entity({ name: 'catalogo_items' })
@Index(['catalogo', 'codigo'], { unique: true })
export class CatalogoItem {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @ManyToOne(() => Catalogo, (c) => c.items, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'catalogo_id' })
  catalogo!: Catalogo;

  @Column({ name: 'codigo', type: 'text', nullable: true })
  codigo?: string | null;

  @Column({ type: 'text' })
  nombre!: string;

  @Column({ type: 'boolean', default: true })
  activo!: boolean;

  @Column({ type: 'smallint', nullable: true })
  orden?: number | null;

  @Column({ type: 'jsonb', default: () => `'{}'::jsonb` })
  meta!: Record<string, any>;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt!: Date;
}
