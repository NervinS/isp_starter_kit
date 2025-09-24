// src/modules/smartolt/smartolt_log.entity.ts
import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn } from 'typeorm';

@Entity({ name: 'smartolt_logs' })
export class SmartoltLog {
  @PrimaryGeneratedColumn('uuid') id: string;
  @CreateDateColumn({ type: 'timestamptz' }) created_at: Date;

  @Column({ type: 'text', nullable: true })   endpoint: string | null;
  @Column({ type: 'jsonb', nullable: true })  request_payload: any | null;
  @Column({ type: 'int', nullable: true })    response_code: number | null;
  @Column({ type: 'jsonb', nullable: true })  response_body: any | null;
  @Column({ type: 'text', nullable: true })   error: string | null;
  @Column({ type: 'text', nullable: true })   request_id: string | null;
}
