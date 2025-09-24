import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

/**
 * Configuración de Cargos
 * Tabla: config_cargos
 */
@Entity('config_cargos')
export class ConfigCargos {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'numeric', default: 0 })
  recontratacion: number;

  @Column({ type: 'numeric', default: 0 })
  instalacion: number;

  @Column({ type: 'numeric', default: 0 })
  mensualidad: number;

  @Column({ type: 'numeric', default: 0 })
  cargoAdicional: number;

  @CreateDateColumn()
  creadoEn: Date;

  @UpdateDateColumn()
  actualizadoEn: Date;
}
