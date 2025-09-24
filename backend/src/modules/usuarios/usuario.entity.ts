import { Entity, PrimaryGeneratedColumn, Column, Index } from 'typeorm';

export type UsuarioEstado =
  | 'nuevo'
  | 'contratado'
  | 'instalado'
  | 'desconectado'
  | 'terminado';

@Entity({ name: 'usuarios' })
export class Usuario {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ length: 20 })
  codigo: string;

  @Column()
  tipo_cliente: string;

  @Column({ length: 120 })
  nombre: string;

  @Column({ length: 120 })
  apellido: string;

  @Column({ length: 30 })
  documento: string;

  @Column({ nullable: true })
  email: string | null;

  @Column({ nullable: true })
  telefono: string | null;

  // Estado del ciclo de vida del usuario/cliente
  @Index('idx_usuarios_estado')
  @Column({
    type: 'enum',
    enum: ['nuevo', 'contratado', 'instalado', 'desconectado', 'terminado'],
    enumName: 'usuario_estado', // Debe coincidir con el TYPE creado en Postgres
    default: 'nuevo',
  })
  estado: UsuarioEstado;
}
