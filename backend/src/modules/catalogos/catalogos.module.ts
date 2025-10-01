// src/modules/catalogos/catalogos.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PassportModule } from '@nestjs/passport';

import { CatalogosService } from './catalogos.service';
import { CatalogosController } from './catalogos.controller';

import { Municipio } from './municipio.entity';
import { Via } from './via.entity';
import { Sector } from './sector.entity';

// Motivos de reagenda (públicos)
import {
  MotivosReagendaPublicControllerKebab,
  MotivosReagendaPublicControllerUnderscore,
} from './motivos-reagenda.public.controller';
// Motivos de reagenda (admin)
import { MotivosReagendaAdminController } from './motivos-reagenda.admin.controller';

// Motivos de anulación (público kebab)
import { MotivosAnulacionPublicControllerKebab } from './motivos-anulacion.public.controller';
// Motivos de anulación (admin)
import { MotivosAnulacionAdminController } from './motivos-anulacion.admin.controller';

// Guards/Estrategia (si ya los usas en otros catálogos)
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

    // Reagenda
    MotivosReagendaPublicControllerKebab,
    MotivosReagendaPublicControllerUnderscore,
    MotivosReagendaAdminController,

    // Anulación
    MotivosAnulacionPublicControllerKebab,
    MotivosAnulacionAdminController,
  ],
  providers: [CatalogosService, JwtStrategy, JwtAuthGuard, RolesGuard],
  exports: [CatalogosService],
})
export class CatalogosModule {}
