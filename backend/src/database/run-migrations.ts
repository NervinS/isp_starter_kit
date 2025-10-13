// src/database/run-migrations.ts
import dataSource from './data-source';

async function main() {
  const ds = await dataSource.initialize();
  try {
    const results = await ds.runMigrations();
    console.log('✅ Migraciones ejecutadas:', results.map(r => r.name));
  } finally {
    await ds.destroy();
  }
}

main().catch((err) => {
  console.error('❌ Error ejecutando migraciones:', err);
  process.exit(1);
});
