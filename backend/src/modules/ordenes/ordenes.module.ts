// src/modules/ordenes/ordenes.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

// Entidades existentes
import { Orden } from './entities/orden.entity';
import { OrdenMaterial } from './entities/orden-material.entity';
import { OrdenCierreIdem } from './entities/orden-cierre-idem.entity';

// Controllers existentes tuyos (no añadimos nuevos aquí)
import { OrdenesController } from './ordenes.controller';

// Servicios existentes
import { OrdenesService } from './ordenes.service';
import { IdempotenciaService } from './services/idempotencia.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Orden,
      OrdenMaterial,
      OrdenCierreIdem, // importante para idempotencia HARD
    ]),
  ],
  controllers: [
    OrdenesController, // dejas tus controladores mapeados en otros módulos (Agenda/Técnicos) como ya están
  ],
  providers: [
    OrdenesService,
    IdempotenciaService,
  ],
  exports: [
    IdempotenciaService,
  ],
})
export class OrdenesModule {}
