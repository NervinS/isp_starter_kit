// src/modules/equipos/equipos.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { EquiposController } from '../../controllers/equipos.controller';
import { EquiposHistorialController } from '../../controllers/equipos.historial.controller';

@Module({
  imports: [TypeOrmModule.forFeature([])],
  controllers: [EquiposController, EquiposHistorialController],
  providers: [],
  exports: [],
})
export class EquiposModule {}
