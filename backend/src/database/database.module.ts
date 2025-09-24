// src/database/database.module.ts
import { Module, OnApplicationShutdown } from '@nestjs/common';
import { DataSource } from 'typeorm';

const dataSourceFactory = {
  provide: DataSource,
  useFactory: async () => {
    // DATABASE_URL=postgres://user:pass@host:5432/db
    const url = process.env.DATABASE_URL;
    if (!url) {
      throw new Error('DATABASE_URL no está definido');
    }

    const ds = new DataSource({
      type: 'postgres',
      url,
      // No registramos entidades porque hacemos SQL crudo (ds.query)
      // Si luego agregas Repositorios, añade entities: [__dirname + '/../**/*.entity{.ts,.js}']
      // y sincronización según tu política de migraciones.
      synchronize: false,
      logging: false,
      // Ajustes de pool sensatos
      extra: {
        max: parseInt(process.env.DB_POOL_MAX || '10', 10),
        idleTimeoutMillis: 30000,
      },
    });

    await ds.initialize();
    return ds;
  },
};

@Module({
  providers: [dataSourceFactory],
  exports: [DataSource],
})
export class DatabaseModule implements OnApplicationShutdown {
  constructor(private readonly ds: DataSource) {}
  async onApplicationShutdown() {
    if (this.ds?.isInitialized) {
      await this.ds.destroy().catch(() => void 0);
    }
  }
}
