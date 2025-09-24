// src/modules/tecnicos/tecnicos.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { TecnicosController } from './tecnicos.controller';
import { TecnicosService } from './tecnicos.service';
import { PdfModule } from '../pdf/pdf.module';

@Module({
  // No usamos entidades TypeORM aquí, pero mantenemos el patrón por consistencia
  imports: [TypeOrmModule.forFeature([]), PdfModule],
  controllers: [TecnicosController],
  providers: [TecnicosService],
  exports: [TecnicosService],
})
export class TecnicosModule {}

