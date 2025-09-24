// src/modules/catalogos/motivos-reagenda.admin.controller.ts
import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CatalogosService } from './catalogos.service';
import {
  CreateCatalogoItemDto,
  UpdateCatalogoItemDto,
} from './dto/catalogo-item.dto';

import { JwtAuthGuard } from '../../common/guards/jwt.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';

@Controller('admin/catalogos/motivos_reagenda/items')
export class MotivosReagendaAdminController {
  constructor(private readonly catalogos: CatalogosService) {}

  // Solo admin
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin') // <-- en minúsculas para que matchee AppRole
  @Get()
  async listarAdmin() {
    const items = await this.catalogos.motivosReagendaListarAdmin();
    return {
      ok: true,
      items: items.map(({ id, codigo, nombre }) => ({ id, codigo, nombre })),
    };
  }

  // Solo admin
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin') // <-- en minúsculas
  @Post()
  async crear(@Body() dto: CreateCatalogoItemDto) {
    const item = await this.catalogos.crearMotivoReagenda(dto);
    return { ok: true, item };
  }

  // Solo admin
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin') // <-- en minúsculas
  @Patch(':id')
  async actualizar(
    @Param('id', ParseIntPipe) id: number, // <- ID numérico
    @Body() dto: UpdateCatalogoItemDto,
  ) {
    const item = await this.catalogos.updateMotivoReagenda(id, dto);
    return { ok: true, item };
  }

  // Solo admin
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin') // <-- en minúsculas
  @Delete(':id')
  async eliminar(@Param('id', ParseIntPipe) id: number) {
    const item = await this.catalogos.deleteMotivoReagenda(id);
    return { ok: true, item };
  }
}
