import { Entity, PrimaryGeneratedColumn, Column, Index } from 'typeorm';

@Entity({ name: 'ordenes' })
export class Orden {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index({ unique: true })
  @Column({ type: 'text', name: 'codigo' })
  codigo!: string;

  @Index()
  @Column({ type: 'text', name: 'estado', default: 'agendada' })
  estado!: string;

  @Column({ type: 'uuid', name: 'tecnico_id', nullable: true })
  tecnicoId!: string | null;

  @Column({ type: 'timestamptz', name: 'iniciada_at', nullable: true })
  iniciadaAt!: Date | null;

  @Column({ type: 'timestamptz', name: 'cerrada_at', nullable: true })
  cerradaAt!: Date | null;

  @Column({ type: 'timestamptz', name: 'created_at', default: () => 'now()' })
  createdAt!: Date;

  @Column({ type: 'timestamptz', name: 'updated_at', default: () => 'now()' })
  updatedAt!: Date;

  @Column({ type: 'text', name: 'firma_key', nullable: true })
  firmaKey!: string | null;

  @Column({ type: 'text', name: 'pdf_url', nullable: true })
  pdfUrl!: string | null;

  @Column({ type: 'text', name: 'pdf_key', nullable: true })
  pdfKey!: string | null;

  @Column({ type: 'numeric', precision: 12, scale: 2, name: 'subtotal', default: 0 })
  subtotal!: string;

  @Column({ type: 'numeric', precision: 12, scale: 2, name: 'total', default: 0 })
  total!: string;

  @Column({ type: 'uuid', name: 'cierre_token', nullable: true })
  cierreToken!: string | null;

  @Column({ type: 'text', name: 'tipo', nullable: true })
  tipo!: string | null; // INS|COR|REC|BAJ|MAN|TRA|CMB|RCT

  @Column({ type: 'jsonb', name: 'form_data', nullable: true })
  formData!: Record<string, unknown> | null;

  // Nuevo: vínculo con usuario
  @Column({ type: 'uuid', name: 'usuario_id', nullable: true })
  usuarioId!: string | null;
}
