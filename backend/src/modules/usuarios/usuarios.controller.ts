import { Controller, Get, Query } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Like } from 'typeorm';
import { Usuario } from './usuario.entity';

@Controller('usuarios')
export class UsuariosController {
  constructor(@InjectRepository(Usuario) private repo: Repository<Usuario>) {}

  @Get()
  async list(@Query('q') q?: string) {
    const where = q
      ? [
          { codigo: Like(`%${q}%`) },
          { nombre: Like(`%${q}%`) },
          { apellido: Like(`%${q}%`) },
          { documento: Like(`%${q}%`) },
        ]
      : {};
    // Nota: TypeORM acepta array de WHERE. En proyectos estrictos puedes tipar:
    // return this.repo.find({ where: (where as any), take: 50, order: { nombre: 'ASC' } });
    return this.repo.find({ where, take: 50, order: { nombre: 'ASC' } });
  }
}
