// src/modules/ordenes/entities/orden.entity.ts
import { Entity, PrimaryGeneratedColumn, Column, Index } from 'typeorm';

const numericToNumber = {
  to: (value?: number | null) => value,
  from: (value?: string | null) =>
    value === null || value === undefined ? null : Number(value),
} as const;

@Entity({ name: 'ordenes' })
export class Orden {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  // En DB ya existe índice único (ordenes_codigo_uk)
  @Index({ unique: true })
  @Column({ type: 'text', name: 'codigo' })
  codigo!: string;

  @Index()
  @Column({ type: 'text', name: 'tipo' })
  // 'INS'|'MAN'|'COR'|'REC'|'BAJ'|'TRA'|'CMB'|'RCT'
  tipo!: string;

  @Index()
  @Column({ type: 'text', name: 'estado' })
  // 'creada'|'agendada'|'en_proceso'|'cerrada'|'anulada'|...
  estado!: string;

  // Índice en DB: idx_ordenes_agendado_para (timestamptz)
  @Index()
  @Column({ type: 'timestamptz', name: 'agendado_para', nullable: true })
  agendadoPara!: Date | null;

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

  // Money-like en DB (numeric). Usamos transformer para exponer number.
  @Column({
    type: 'numeric',
    name: 'subtotal',
    default: 0,
    transformer: numericToNumber,
  })
  subtotal!: number;

  @Column({
    type: 'numeric',
    name: 'total',
    default: 0,
    transformer: numericToNumber,
  })
  total!: number;

  @Column({ type: 'timestamptz', name: 'created_at', default: () => 'now()' })
  createdAt!: Date;

  @Column({ type: 'timestamptz', name: 'updated_at', default: () => 'now()' })
  updatedAt!: Date;

  @Column({ type: 'text', name: 'motivo_cancelacion', nullable: true })
  motivoCancelacion!: string | null;

  @Column({ type: 'text', name: 'motivo_anulacion', nullable: true })
  motivoAnulacion!: string | null;

  @Column({ type: 'int', name: 'motivo_anulacion_id', nullable: true })
  motivoAnulacionId!: number | null;

  // Índice en DB: idx_ordenes_usuario
  @Index()
  @Column({ type: 'uuid', name: 'usuario_id', nullable: true })
  usuarioId!: string | null;

  // En DB es integer
  @Column({ type: 'int', name: 'tecnico_id', nullable: true })
  tecnicoId!: number | null;

  // Índice en DB: idx_ordenes_venta
  @Index()
  @Column({ type: 'uuid', name: 'venta_id', nullable: true })
  ventaId!: string | null;

  // Campos JSON
  @Column({ type: 'jsonb', name: 'payload_abierto', nullable: true })
  payloadAbierto!: Record<string, unknown> | null;

  @Column({ type: 'jsonb', name: 'payload_cierre', nullable: true })
  payloadCierre!: Record<string, unknown> | null;

  @Column({ type: 'jsonb', name: 'evidencias', nullable: true })
  evidencias!: Record<string, unknown> | null;

  // Archivos
  @Column({ type: 'text', name: 'pdf_url', nullable: true })
  pdfUrl!: string | null;

  @Column({ type: 'text', name: 'pdf_key', nullable: true })
  pdfKey!: string | null;

  @Column({ type: 'text', name: 'firma_key', nullable: true })
  firmaKey!: string | null;
}
