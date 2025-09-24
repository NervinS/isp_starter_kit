// src/modules/inventario/inventario.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { InventarioController } from './inventario.controller';
import { InventarioService } from './inventario.service';

import { StockTecnico } from './stock-tecnico.entity';
import { Tecnico } from '../tecnicos/tecnico.entity';
import { Material } from '../materiales/material.entity';

@Module({
  // Registramos los repos por si el service (ahora o después) usa @InjectRepository
  imports: [TypeOrmModule.forFeature([StockTecnico, Tecnico, Material])],
  controllers: [InventarioController],
  providers: [InventarioService],
  // Exportamos para que otros módulos puedan usar el service o los repos si los requieren
  exports: [InventarioService, TypeOrmModule],
})
export class InventarioModule {}
