// src/modules/inventario/inventario.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { InventarioService } from './inventario.service';
import { InventarioController } from './inventario.controller';
import { KardexMaterialController } from './kardex-material.controller';

// Si tienes entidades específicas, impórtalas aquí:
// import { AlgoEntity } from './entities/algo.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([]),
  ],
  controllers: [
    InventarioController,      // existente
    KardexMaterialController,  // ⬅️ nuevo (read-only)
  ],
  providers: [InventarioService],
  exports: [InventarioService],
})
export class InventarioModule {}
