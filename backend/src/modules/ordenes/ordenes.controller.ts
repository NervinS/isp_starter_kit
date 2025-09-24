import { Body, Controller, Param, Put } from '@nestjs/common';
import { OrdenesService } from './ordenes.service';

class CerrarDto {
  tecnicoId!: string;
  materiales?: { materialIdInt: number; cantidad: number }[];
  evidenciasBase64?: string[];
  firmaBase64?: string | null;
}

@Controller('ordenes')
export class OrdenesController {
  constructor(private readonly svc: OrdenesService) {}

  // Cierre por código para Admin
  @Put(':codigo/cerrar')
  async cerrarPorCodigo(@Param('codigo') codigo: string, @Body() dto: CerrarDto) {
    return this.svc.cerrarCompletoAdmin(codigo, { tecnicoId: dto.tecnicoId });
  }
}
