import { Entity, Column, PrimaryGeneratedColumn, Index } from 'typeorm';

@Entity('municipios')
export class Municipio {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  // Ej: 'BARRANQUILLA'. Es la clave a la que apunta sectores.municipio_codigo
  @Index()
  @Column({ type: 'text' })
  codigo: string;

  @Index()
  @Column({ type: 'text' })
  nombre: string;

  @Column({ type: 'boolean', default: true })
  activo: boolean;
}
