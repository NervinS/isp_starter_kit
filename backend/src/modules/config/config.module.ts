// src/modules/config/config.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigCargosService } from './config.service';

// Si tu servicio usa entidades (por ejemplo ConfigCargos), inclúyelas aquí.
// import { ConfigCargos } from './entities/config-cargos.entity';

@Module({
  imports: [
    // TypeOrmModule.forFeature([ConfigCargos]),
  ],
  providers: [ConfigCargosService],
  exports: [ConfigCargosService], // ⬅️ EXPORTA el service
})
export class ConfigModule {}
