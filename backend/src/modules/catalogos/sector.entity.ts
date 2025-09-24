import { Entity, Column, PrimaryGeneratedColumn, Index } from 'typeorm';

@Entity('sectores')
export class Sector {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  // FK lógica → municipios.codigo (texto)
  @Index()
  @Column({ type: 'text', name: 'municipio_codigo' })
  municipioCodigo: string;

  // 'BARRIO' | 'CONJUNTO' | null
  @Index()
  @Column({ type: 'text', nullable: true })
  zona: string | null;

  @Index()
  @Column({ type: 'text' })
  nombre: string;

  @Column({ type: 'boolean', default: true })
  activo: boolean;
}
