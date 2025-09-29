// src/modules/inventario/inventario.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { InventarioController } from './inventario.controller';
import { InventarioService } from './inventario.service';
import { Tecnico } from '../tecnicos/tecnico.entity';
import { Material } from '../materiales/material.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([Tecnico, Material]),
  ],
  controllers: [InventarioController],
  providers: [InventarioService],
  exports: [InventarioService],
})
export class InventarioModule {}
