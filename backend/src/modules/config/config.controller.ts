import { Body, Controller, Get, Patch } from '@nestjs/common';
import { ConfigCargosService } from './config.service';

@Controller('config')
export class ConfigCargosController {
  constructor(private readonly svc: ConfigCargosService) {}

  @Get('cargos')
  obtener() {
    return this.svc.obtenerOCrear();
  }

  @Patch('cargos')
  actualizar(@Body() body: Partial<{ recontratacion: number; instalacion: number; mensualidad: number; cargoAdicional: number }>) {
    return this.svc.actualizar(body as any);
  }
}
