import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ValidationPipe } from '@nestjs/common';
import { useContainer } from 'class-validator';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { cors: true });

  useContainer(app.select(AppModule), { fallbackOnErrors: true });

  app.setGlobalPrefix('v1');

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
      transformOptions: { enableImplicitConversion: true },
    }),
  );

  // Helmet opcional
  try {
    const helmetMod: any = await import('helmet');
    const helmet = (helmetMod && (helmetMod.default || helmetMod)) as any;
    if (helmet) app.use(helmet());
  } catch {
    console.warn('[helmet] no instalado — continuo sin helmet');
  }

  // Swagger sólo si está ON (y sin ruta manual de JSON)
  try {
    if (process.env.SWAGGER_ON !== '0') {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const swagger = require('@nestjs/swagger') as typeof import('@nestjs/swagger');
      const builder = new swagger.DocumentBuilder()
        .setTitle('ISP Starter Kit API')
        .setDescription('Endpoints del ISP (FTTH) — Admin/Técnico/Jobs')
        .setVersion('1.0.0')
        .addBearerAuth()
        .build();

      const document = swagger.SwaggerModule.createDocument(app, builder);
      swagger.SwaggerModule.setup('/v1/docs', app, document);
      console.log('[Swagger] Docs en http://127.0.0.1:3000/v1/docs');
    }
  } catch (err) {
    console.warn('[Swagger] no habilitado:', err?.message || err);
  }

  const host = process.env.HOST || '0.0.0.0';
  const port = parseInt(process.env.PORT || '3000', 10);
  await app.listen(port, host);
  console.log(`API running on http://${host}:${port}/v1`);
}

bootstrap();
