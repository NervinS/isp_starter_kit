// src/modules/ordenes/entities/orden-equipos.entity.ts
import { Entity, PrimaryGeneratedColumn, Column, Index } from 'typeorm';

@Entity({ name: 'orden_equipos' })
export class OrdenEquipo {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Index()
  @Column({ type: 'uuid', name: 'orden_id' })
  ordenId!: string;

  @Column({ type: 'text', name: 'equipo_tipo' })
  equipoTipo!: 'ONT' | 'REPEATER';

  @Index()
  @Column({ type: 'text', name: 'serial' })
  serial!: string;

  @Column({ type: 'text', name: 'accion' })
  accion!: 'asignar' | 'retirar' | 'mantener';

  @Column({ type: 'boolean', name: 'aplicado', default: false })
  aplicado!: boolean;
}
