import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Material } from './material.entity';

type CreateMaterialDto = {
  codigo: string;
  nombre: string;
  precio?: number | string;
  // ❌ ignoramos unidad/activo si vinieran en algún DTO anterior
};

type UpdateMaterialDto = Partial<CreateMaterialDto>;

@Injectable()
export class MaterialesService {
  constructor(
    @InjectRepository(Material)
    private readonly repo: Repository<Material>,
  ) {}

  async list(): Promise<Material[]> {
    // Selección explícita para evitar columnas inexistentes
    return this.repo.find({
      select: ['id', 'codigo', 'nombre', 'precio', 'createdAt', 'updatedAt'],
      order: { id: 'ASC' },
    });
  }

  async create(dto: CreateMaterialDto): Promise<Material> {
    const entity = this.repo.create({
      codigo: dto.codigo,
      nombre: dto.nombre,
      // precio es numeric en PG (TypeORM lo devuelve string); normalizamos a string
      precio: dto.precio !== undefined ? String(dto.precio) : '0',
      // ❌ no seteamos unidad/activo
    });
    return this.repo.save(entity);
  }

  async update(id: number, dto: UpdateMaterialDto): Promise<Material> {
    const mat = await this.repo.findOneOrFail({ where: { id } });
    if (dto.codigo !== undefined) mat.codigo = dto.codigo;
    if (dto.nombre !== undefined) mat.nombre = dto.nombre;
    if (dto.precio !== undefined) mat.precio = String(dto.precio);
    // ❌ no tocamos unidad/activo
    return this.repo.save(mat);
  }
}
