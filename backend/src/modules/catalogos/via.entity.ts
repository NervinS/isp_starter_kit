import { Entity, Column, PrimaryGeneratedColumn, Index } from 'typeorm';

@Entity('vias')
export class Via {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column({ type: 'text' })
  codigo: string;

  @Index()
  @Column({ type: 'text' })
  nombre: string;

  @Column({ type: 'boolean', default: true })
  activo: boolean;
}
