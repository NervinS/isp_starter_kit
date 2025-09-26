// src/modules/tecnicos/tecnicos.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { TecnicosController } from './tecnicos.controller';
import { TecnicosService } from './tecnicos.service';

import { PdfModule } from '../pdf/pdf.module';
import { InventarioModule } from '../inventario/inventario.module';

import { Orden } from '../ordenes/entities/orden.entity';
import { Tecnico } from './tecnico.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([Orden, Tecnico]),
    PdfModule,
    InventarioModule,
  ],
  controllers: [TecnicosController],
  providers: [TecnicosService],
  exports: [TecnicosService],
})
export class TecnicosModule {}
