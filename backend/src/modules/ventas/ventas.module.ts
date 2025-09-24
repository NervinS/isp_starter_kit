import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { VentasController } from './ventas.controller';
import { Venta } from './ventas.entity';
import { Usuario } from '../usuarios/usuario.entity';
import { Orden } from '../ordenes/entities/orden.entity';
import { Plan } from '../planes/plan.entity';

// Servicios usados por VentasController
import { MinioService } from '../storage/minio.service';
import { PdfService } from '../pdf/pdf.service';

// 🔗 Necesarios para crear/agendar órdenes al pagar
import { OrdenesModule } from '../ordenes/ordenes.module';
import { TecnicosModule } from '../tecnicos/tecnicos.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Venta, Usuario, Orden, Plan]),
    // forwardRef por si hay dependencias cruzadas
    forwardRef(() => OrdenesModule),
    forwardRef(() => TecnicosModule),
  ],
  controllers: [VentasController],
  providers: [MinioService, PdfService],
})
export class VentasModule {}
