// src/app.module.ts
import { Module, NestModule, MiddlewareConsumer, RequestMethod } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { MetricsModule } from './modules/metrics/metrics.module';
import { ConfigModule } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';

import { VentasModule } from './modules/ventas/ventas.module';
import { HealthModule } from './modules/health/health.module';
import { CatalogosModule } from './modules/catalogos/catalogos.module';
import { AgendaModule } from './modules/agenda/agenda.module';
import { TecnicosModule } from './modules/tecnicos/tecnicos.module';
import { MaterialesModule } from './modules/materiales/materiales.module';
import { InventarioModule } from './modules/inventario/inventario.module';
import { OrdenesModule } from './modules/ordenes/ordenes.module';
import { JobsModule } from './modules/jobs/jobs.module'; // ⬅️ ya existente
import { EquiposModule } from './modules/equipos/equipos.module'; // ⬅️ NUEVO

import { RequestIdMiddleware } from './common/middleware/request-id.middleware';
import { LoggerMiddleware } from './common/middleware/logger.middleware';
import { IdempotencyReplayedInterceptor } from './common/interceptors/idempotency-replayed.interceptor';

function maskDbUrl(url?: string) {
  if (!url) return '';
  // oculta password si viene en formato postgresql://user:pass@host/db
  return url.replace(/(:\/\/[^:@]+:)[^@]+@/, '$1***@');
}

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      expandVariables: true,
    }),
    TypeOrmModule.forRootAsync({
      useFactory: async () => {
        const url = process.env.DATABASE_URL ?? process.env.DBURL ?? 'postgresql://ispuser:ispuser@db:5432/ispdb';

        // SSL opcional: establece DATABASE_SSL=true para forzar SSL (útil en PaaS)
        const sslEnabled =
          String(process.env.DATABASE_SSL ?? process.env.PGSSL ?? '').toLowerCase() === 'true';

        // Pool máximo configurable (por defecto 10)
        const poolMax = parseInt(process.env.PGPOOL_MAX ?? '10', 10);

        // Logs amistosos
        // eslint-disable-next-line no-console
        console.log(`[DB] URL: ${maskDbUrl(url)} | SSL=${sslEnabled ? 'on' : 'off'} | pool.max=${poolMax}`);

        return {
          type: 'postgres' as const,
          url,
          autoLoadEntities: true,
          synchronize: false,            // Nunca en prod
          keepConnectionAlive: true,     // Mantiene conexión entre recargas
          retryAttempts: 5,
          retryDelay: 3000,
          ssl: sslEnabled ? { rejectUnauthorized: false } : undefined,
          extra: { max: poolMax },
        };
      },
    }),
    // Módulos de dominio
    VentasModule,
    HealthModule,
    CatalogosModule,
    AgendaModule,
    TecnicosModule,
    MaterialesModule,
    InventarioModule,
    OrdenesModule,
    MetricsModule,
    JobsModule,
    EquiposModule, // ⬅️ NUEVO
  ],
  providers: [
    // Interceptor global: añade el header Idempotency-Replayed: true cuando body._idempotent === true
    {
      provide: APP_INTERCEPTOR,
      useClass: IdempotencyReplayedInterceptor,
    },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(RequestIdMiddleware, LoggerMiddleware)
      .forRoutes({ path: '*', method: RequestMethod.ALL });
  }
}
