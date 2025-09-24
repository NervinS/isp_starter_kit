// src/modules/tecnicos/tecnico.entity.ts
import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'tecnicos' })
export class Tecnico {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'text', unique: true })
  codigo!: string;

  @Column({ type: 'text', nullable: true })
  nombre?: string;

  @Column({ type: 'text', nullable: true })
  telefono?: string;

  @Column({ type: 'timestamptz', default: () => 'now()' })
  created_at!: Date;

  @Column({ type: 'timestamptz', default: () => 'now()' })
  updated_at!: Date;
}

