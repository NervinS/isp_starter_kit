// src/modules/ordenes/orden.entity.ts
import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

// Alinear con lo que realmente hay en DB/JSON: dejar tipos flexibles
export type OrdenTipo = string;    // p.ej. "INS", "MAN", etc.
export type OrdenEstado = string;  // p.ej. "agendada", "cerrada", "anulada", etc.
export type Turno = string | null; // p.ej. "AM", "PM", "am", "pm" o null

@Entity({ name: 'ordenes' })
export class Orden {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index({ unique: true })
  @Column({ type: 'varchar', length: 64, unique: true })
  codigo!: string;

  @Column({ type: 'varchar', length: 16 })
  tipo!: OrdenTipo;

  @Column({ type: 'varchar', length: 32 })
  estado!: OrdenEstado;

  // fecha (YYYY-MM-DD) a la que quedó agendada
  @Column({ name: 'agendado_para', type: 'date', nullable: true })
  agendadoPara!: string | null;

  // AM/PM (o am/pm)
  @Column({ type: 'varchar', length: 8, nullable: true })
  turno!: Turno;

  @Column({ name: 'agendada_at', type: 'timestamp', nullable: true })
  agendadaAt!: Date | null;

  @Column({ name: 'iniciada_at', type: 'timestamp', nullable: true })
  iniciadaAt!: Date | null;

  @Column({ name: 'cerrada_at', type: 'timestamp', nullable: true })
  cerradaAt!: Date | null;

  @Column({ name: 'cancelada_at', type: 'timestamp', nullable: true })
  canceladaAt!: Date | null;

  @Column({
    name: 'motivo_cancelacion',
    type: 'varchar',
    length: 256,
    nullable: true,
  })
  motivoCancelacion!: string | null;

  // algunos GET devuelven también 'motivoAnulacion'
  @Column({
    name: 'motivo_anulacion',
    type: 'varchar',
    length: 256,
    nullable: true,
  })
  motivoAnulacion!: string | null;

  @Column({ name: 'motivo_anulacion_id', type: 'int', nullable: true })
  motivoAnulacionId!: number | null;

  // según tus respuestas, ventaId es UUID (o null)
  @Column({ name: 'venta_id', type: 'uuid', nullable: true })
  ventaId!: string | null;

  // opcionalmente usuarioId/tecnicoId pueden ser UUID/text
  @Column({ name: 'usuario_id', type: 'uuid', nullable: true })
  usuarioId!: string | null;

  @Column({ name: 'tecnico_id', type: 'uuid', nullable: true })
  tecnicoId!: string | null;

  // payloads abiertos/cierre (jsonb), presentes en tu GET
  @Column({ name: 'payload_abierto', type: 'jsonb', nullable: true })
  payloadAbierto!: Record<string, unknown> | null;

  @Column({ name: 'payload_cierre', type: 'jsonb', nullable: true })
  payloadCierre!: Record<string, unknown> | null;

  // evidencias (jsonb in-line)
  @Column({ type: 'jsonb', nullable: true })
  evidencias!: Record<string, unknown> | null;

  @Column({ name: 'pdf_url', type: 'text', nullable: true })
  pdfUrl!: string | null;

  @Column({ name: 'pdf_key', type: 'text', nullable: true })
  pdfKey!: string | null;

  @Column({ name: 'firma_key', type: 'text', nullable: true })
  firmaKey!: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamp' })
  createdAt!: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamp' })
  updatedAt!: Date;
}
