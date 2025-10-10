// src/modules/equipos/equipos.module.ts
import { Module } from '@nestjs/common';
import { EquiposController } from '../../controllers/equipos.controller';

@Module({
  controllers: [EquiposController],
})
export class EquiposModule {}
