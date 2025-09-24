import { Entity, PrimaryGeneratedColumn, Column } from 'typeorm';

@Entity({ name: 'evidencias' })
export class Evidencia {
  @PrimaryGeneratedColumn('uuid') id: string;
  @Column({ type: 'uuid' }) orden_id: string;
  @Column({ length: 16 }) tipo: 'foto' | 'firma';
  @Column({ length: 255 }) object_key: string;
  @Column({ length: 80, nullable: true }) mime?: string;
  @Column({ type: 'int', nullable: true }) size?: number;
  @Column({ type: 'timestamptz', default: () => 'now()' }) created_at: Date;
}
