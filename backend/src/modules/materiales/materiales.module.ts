// src/modules/materiales/materiales.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { Material } from './material.entity';
import { MaterialesService } from './materiales.service';
import { MaterialesController } from './materiales.controller';

// Controller nuevo para /v1/materiales/disponibles
// (lo crearás en src/controllers/materiales.disponibles.controller.ts)
import { MaterialesDisponiblesController } from '../../controllers/materiales.disponibles.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Material])],
  controllers: [MaterialesController, MaterialesDisponiblesController],
  providers: [MaterialesService],
})
export class MaterialesModule {}
