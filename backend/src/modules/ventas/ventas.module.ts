// src/modules/ventas/ventas.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { VentasController } from './ventas.controller';
import { Venta } from './ventas.entity';

@Module({
  imports: [TypeOrmModule.forFeature([Venta])],
  controllers: [VentasController],
  providers: [],
  exports: [],
})
export class VentasModule {}
