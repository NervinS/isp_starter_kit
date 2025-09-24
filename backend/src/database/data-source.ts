// src/database/data-source.ts
import 'reflect-metadata';
import { DataSource } from 'typeorm';

const dataSource = new DataSource({
  type: 'postgres',
  host: process.env.DB_HOST || 'db',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  username: process.env.DB_USER || 'ispuser',
  password: process.env.DB_PASS || 'isppass',
  database: process.env.DB_NAME || 'ispdb',
  ssl: false,

  // IMPORTANTE: en entornos con datos reales, mantener false
  synchronize: false,

  // Como ejecutaremos el CLI con ts-node/register,
  // podemos usar globs .ts
  entities: [process.env.NODE_ENV === 'development' ? 'src/**/*.entity.ts' : 'dist/**/*.entity.js'],
  migrations: [process.env.NODE_ENV === 'development' ? 'src/**/migrations/*.ts' : 'dist/database/migrations/*.js'],
  migrationsTableName: 'typeorm_migrations',
  logging: ['error'],
});

export default dataSource;

