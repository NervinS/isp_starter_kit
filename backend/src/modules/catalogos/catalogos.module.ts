// src/modules/catalogos/catalogos.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PassportModule } from '@nestjs/passport';

import { CatalogosService } from './catalogos.service';
import { CatalogosController } from './catalogos.controller';

import { Municipio } from './municipio.entity';
import { Via } from './via.entity';
import { Sector } from './sector.entity';

// Controladores públicos (kebab y underscore)
import {
  MotivosReagendaPublicControllerKebab,
  MotivosReagendaPublicControllerUnderscore,
} from './motivos-reagenda.public.controller';

// Controlador admin (protegido)
import { MotivosReagendaAdminController } from './motivos-reagenda.admin.controller';

// Guards y estrategia JWT
import { JwtAuthGuard } from '../../common/guards/jwt.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { JwtStrategy } from '../../common/strategies/jwt.strategy';

@Module({
  imports: [
    TypeOrmModule.forFeature([Municipio, Via, Sector]),
    PassportModule.register({ defaultStrategy: 'jwt' }),
  ],
  controllers: [
    CatalogosController,
    MotivosReagendaPublicControllerKebab,
    MotivosReagendaPublicControllerUnderscore,
    MotivosReagendaAdminController,
  ],
  providers: [
    CatalogosService,
    JwtStrategy,
    JwtAuthGuard,
    RolesGuard,
  ],
  exports: [CatalogosService],
})
export class CatalogosModule {}
