// src/modules/ordenes/entities/orden.entity.ts
import { Entity, PrimaryGeneratedColumn, Column, Index } from 'typeorm';

@Entity({ name: 'ordenes' })
export class Orden {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index({ unique: true })
  @Column({ type: 'text', name: 'codigo' })
  codigo!: string;

  @Index()
  @Column({ type: 'text', name: 'tipo' })
  tipo!: 'INS'|'MAN'|'COR'|'REC'|'BAJ'|'TRA'|'CMB'|'RCT';

  @Index()
  @Column({ type: 'text', name: 'estado' })
  estado!: string; // 'creada'|'agendada'|'en_proceso'|'cerrada'|'anulada'...

  @Column({ type: 'date', name: 'agendado_para', nullable: true })
  agendadoPara!: string | null;

  @Column({ type: 'text', name: 'turno', nullable: true })
  turno!: string | null;

  @Column({ type: 'timestamptz', name: 'agendada_at', nullable: true })
  agendadaAt!: Date | null;

  @Column({ type: 'timestamptz', name: 'iniciada_at', nullable: true })
  iniciadaAt!: Date | null;

  @Column({ type: 'timestamptz', name: 'cerrada_at', nullable: true })
  cerradaAt!: Date | null;

  @Column({ type: 'timestamptz', name: 'cancelada_at', nullable: true })
  canceladaAt!: Date | null;

  @Column({ type: 'timestamptz', name: 'created_at', default: () => 'now()' })
  createdAt!: Date;

  @Column({ type: 'timestamptz', name: 'updated_at', default: () => 'now()' })
  updatedAt!: Date;

  @Column({ type: 'text', name: 'motivo_cancelacion', nullable: true })
  motivoCancelacion!: string | null;

  @Column({ type: 'uuid', name: 'usuario_id', nullable: true })
  usuarioId!: string | null;

  @Column({ type: 'uuid', name: 'tecnico_id', nullable: true })
  tecnicoId!: string | null;

  @Column({ type: 'uuid', name: 'venta_id', nullable: true })
  ventaId!: string | null;

  @Column({ type: 'text', name: 'motivo_anulacion', nullable: true })
  motivoAnulacion!: string | null;

  @Column({ type: 'int', name: 'motivo_anulacion_id', nullable: true })
  motivoAnulacionId!: number | null;

  // Nuevos (ya migrados)
  @Column({ type: 'jsonb', name: 'payload_abierto', nullable: true })
  payloadAbierto!: Record<string, unknown> | null;

  @Column({ type: 'jsonb', name: 'payload_cierre', nullable: true })
  payloadCierre!: Record<string, unknown> | null;

  @Column({ type: 'jsonb', name: 'evidencias', nullable: true })
  evidencias!: Record<string, unknown> | null;

  @Column({ type: 'text', name: 'pdf_url', nullable: true })
  pdfUrl!: string | null;

  @Column({ type: 'text', name: 'pdf_key', nullable: true })
  pdfKey!: string | null;

  @Column({ type: 'text', name: 'firma_key', nullable: true })
  firmaKey!: string | null;
}
