import { Entity, PrimaryGeneratedColumn, Column } from 'typeorm';

@Entity({ name: 'planes' })
export class Plan {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  codigo: string;

  @Column()
  nombre: string;

  @Column({ type: 'int' })
  vel_mbps: number;

  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  alta_costo: string; // TypeORM mapea numeric a string en TS

  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 })
  mensual: string;

  @Column({ type: 'boolean', default: true })
  activo: boolean;

  @Column({ type: 'text', default: 'internet' })
  tipo: string;
}
