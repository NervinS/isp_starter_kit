import { Controller, Get, Param, Query } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Plan } from './plan.entity';
import { Roles } from '../../common/decorators/roles.decorator';

@Controller('planes')
export class PlanesController {
  constructor(
    @InjectRepository(Plan) private readonly plans: Repository<Plan>,
  ) {}

  // GET /v1/planes?activos=1
  @Get()
  @Roles('admin', 'ventas', 'tecnico')
  async list(@Query('activos') activos?: string) {
    const where = activos === '1' || activos === 'true' ? { activo: true } : {};
    const items = await this.plans.find({
      where: where as any,
      order: { vel_mbps: 'ASC' } as any,
    });

    // Formato liviano para el front
    return items.map((p) => ({
      codigo: p.codigo,
      nombre: p.nombre,
      vel_mbps: p.vel_mbps,
      alta_costo: p.alta_costo,
      mensual: p.mensual,
      tipo: p.tipo,
      activo: p.activo,
    }));
  }

  // GET /v1/planes/:codigo
  @Get(':codigo')
  @Roles('admin', 'ventas', 'tecnico')
  async one(@Param('codigo') codigo: string) {
    const p = await this.plans.findOne({ where: { codigo } });
    if (!p) return { ok: false, message: 'No existe' };
    return p;
  }
}
