// src/modules/materiales/materiales.controller.ts
import { Controller, Get } from '@nestjs/common';
import { MaterialesService } from './materiales.service';

@Controller('materiales') // <-- sin 'v1/'
export class MaterialesController {
  constructor(private readonly materiales: MaterialesService) {}

  @Get()
  async list() {
    const mats = await this.materiales.list();
    return mats.map((m) => ({
      id: m.id,
      codigo: m.codigo,
      nombre: m.nombre,
      precio: m.precio,
    }));
  }
}
