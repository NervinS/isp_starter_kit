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
import { PdfModule } from '../pdf/pdf.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Orden,
      OrdenMaterial,
      OrdenCierreIdem, // idempotencia/auditoría
    ]),
    PdfModule,
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
    // Exportamos servicios que podrían ser usados por otros módulos (sin romper compat)
    IdempotenciaService,
    OrdenesService,
    TypeOrmModule, // export útil si otro módulo importa este y requiere las entidades
  ],
})
export class OrdenesModule {}
