// src/database/data-source.ts
import 'reflect-metadata';
import { DataSource } from 'typeorm';

const isProd = process.env.NODE_ENV === 'production';

const dataSource = new DataSource({
  type: 'postgres',
  host: process.env.DB_HOST || 'db',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  username: process.env.DB_USER || 'ispuser',
  password: process.env.DB_PASS || 'isppass',
  database: process.env.DB_NAME || 'ispdb',
  ssl: false,

  // Nunca sincronizar en producción; usamos migraciones.
  synchronize: false,
  migrationsRun: false,

  // Entities: src en dev, dist en prod
  entities: isProd ? ['dist/**/*.entity.js'] : ['src/**/*.entity.ts'],

  // Migrations: apuntar SOLO a /database/migrations
  migrations: isProd
    ? ['dist/database/migrations/*.js']
    : ['src/database/migrations/*.ts'],

  // Tabla donde TypeORM lleva el registro
  migrationsTableName: 'typeorm_migrations',

  // Logging sólo de errores (ajustable)
  logging: ['error'],
});

export default dataSource;
