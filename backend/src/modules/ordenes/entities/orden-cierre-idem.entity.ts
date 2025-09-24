// src/modules/ordenes/entities/orden-cierre-idem.entity.ts
import { Column, CreateDateColumn, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'orden_cierres_idem' })
@Index(['orden_codigo', 'payload_hash'], { unique: true })
export class OrdenCierreIdem {
  @PrimaryGeneratedColumn('increment')
  id!: number;

  @Column({ type: 'varchar', length: 32 })
  orden_codigo!: string;

  @Column({ type: 'varchar', length: 64 })
  payload_hash!: string;

  @Index()
  @Column({ type: 'varchar', length: 128, nullable: true })
  idempotency_key!: string | null;

  @CreateDateColumn({ type: 'timestamptz', name: 'first_seen_at' })
  first_seen_at!: Date;

  @Column({ type: 'int', nullable: true })
  response_status!: number | null;

  @Column({ type: 'jsonb', nullable: true })
  response_body!: any | null;
}
