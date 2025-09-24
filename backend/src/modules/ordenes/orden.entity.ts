import { Entity, PrimaryGeneratedColumn, Column, Index } from 'typeorm';

/**
 * Mapea "ordenes" (uuid + snake_case) a propiedades camelCase
 * que usa el servicio Nest.
 */
@Entity('ordenes')
export class Orden {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index({ unique: true })
  @Column({ type: 'text' })
  codigo!: string;

  @Index()
  @Column({ type: 'text', default: 'agendada' })
  estado!: string;

  /** tecnico_id -> tecnicoId */
  @Index()
  @Column({ name: 'tecnico_id', type: 'uuid', nullable: true })
  tecnicoId!: string | null;

  /** iniciada_at -> iniciadaAt */
  @Column({ name: 'iniciada_at', type: 'timestamptz', nullable: true })
  iniciadaAt!: Date | null;

  /** cerrada_at -> cerradaAt */
  @Column({ name: 'cerrada_at', type: 'timestamptz', nullable: true })
  cerradaAt!: Date | null;

  /** created_at -> creadoAt (¡ojo: nombre en español porque así lo usa el servicio!) */
  @Column({ name: 'created_at', type: 'timestamptz', default: () => 'now()' })
  creadoAt!: Date;

  /** updated_at -> actualizadoAt (por si lo usan en selects/ordenamiento) */
  @Column({ name: 'updated_at', type: 'timestamptz', default: () => 'now()' })
  actualizadoAt!: Date;

  /** firma_key -> firmaImgKey (lo actualizan al cerrar) */
  @Column({ name: 'firma_key', type: 'text', nullable: true })
  firmaImgKey!: string | null;

  /** pdf_url -> pdfUrl (suele setearse al cerrar) */
  @Column({ name: 'pdf_url', type: 'text', nullable: true })
  pdfUrl!: string | null;

  /** pdf_key -> pdfKey (suele setearse al cerrar) */
  @Column({ name: 'pdf_key', type: 'text', nullable: true })
  pdfKey!: string | null;

  /** totales (como string porque numeric) */
  @Column({ name: 'subtotal', type: 'numeric', precision: 12, scale: 2, default: 0 })
  subtotal!: string;

  @Column({ name: 'total', type: 'numeric', precision: 12, scale: 2, default: 0 })
  total!: string;

  /** extras comunes que podrían leerse en servicios; quedan opcionales */
  @Column({ name: 'cierre_token', type: 'uuid', nullable: true })
  cierreToken!: string | null;

  @Column({ name: 'tipo', type: 'text', nullable: true })
  tipo!: string | null;

  @Column({ name: 'form_data', type: 'jsonb', nullable: true })
  formData!: Record<string, any> | null;
}
