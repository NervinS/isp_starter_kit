// src/modules/materiales/materiales.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { Material } from './material.entity';
import { MaterialesService } from './materiales.service';
import { MaterialesController } from './materiales.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Material])],
  controllers: [MaterialesController],
  providers: [MaterialesService],
  // Exportamos el service (y el TypeOrmModule) para que otros módulos puedan usar el repo si hace falta.
  exports: [MaterialesService, TypeOrmModule],
})
export class MaterialesModule {}
