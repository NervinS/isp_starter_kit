// src/modules/ordenes/ordenes.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

// Entidades existentes
import { Orden } from './entities/orden.entity';
import { OrdenMaterial } from './entities/orden-material.entity';
import { OrdenCierreIdem } from './entities/orden-cierre-idem.entity';

// Controlador transversal (nuevo contrato Fase 1)
import { OrdenesTransversalController } from './ordenes.transversal.controller';

// Servicios
import { OrdenesService } from './ordenes.service';
import { IdempotenciaService } from './services/idempotencia.service';
import { OrdenesTransversalService } from './ordenes.transversal.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Orden,
      OrdenMaterial,
      OrdenCierreIdem, // idempotencia/auditoría
    ]),
  ],
  controllers: [
    // 👇 sólo exponemos el controlador transversal para evitar colisiones con el legado
    OrdenesTransversalController,
  ],
  providers: [
    OrdenesService,              // se mantiene disponible por si otros módulos lo usan
    IdempotenciaService,
    OrdenesTransversalService,   // servicio nuevo
  ],
  exports: [
    IdempotenciaService,
  ],
})
export class OrdenesModule {}
