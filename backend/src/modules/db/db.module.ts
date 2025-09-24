// backend/src/modules/db/db.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config';

@Module({
  imports: [
    // Carga variables de entorno de forma global (si ya lo tienes global, no pasa nada)
    ConfigModule.forRoot({ isGlobal: true }),

    // Conexión TypeORM con autoLoadEntities para que registre todas las entidades
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (cfg: ConfigService) => ({
        type: 'postgres',
        host: cfg.get<string>('DB_HOST', '127.0.0.1'),
        port: parseInt(cfg.get<string>('DB_PORT', '5432'), 10),
        username: cfg.get<string>('DB_USER', 'ispuser'),
        password: cfg.get<string>('DB_PASS', ''),
        database: cfg.get<string>('DB_NAME', 'ispdb'),

        // 👇 clave para tu error:
        autoLoadEntities: true,

        // Mantén en false en producción
        synchronize: false,

        // Opcional útil en dev
        // logging: true,
      }),
    }),
  ],
})
export class DbModule {}
