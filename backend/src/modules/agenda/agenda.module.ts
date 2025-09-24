import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { AgendaController } from './agenda.controller';
import { AgendaService } from './agenda.service';

import { Orden } from '../ordenes/entities/orden.entity';
import { Tecnico } from '../tecnicos/tecnico.entity';
import { Usuario } from '../usuarios/usuario.entity';

@Module({
  imports: [TypeOrmModule.forFeature([Orden, Tecnico, Usuario])],
  controllers: [AgendaController],
  providers: [AgendaService],
  exports: [AgendaService],
})
export class AgendaModule {}
