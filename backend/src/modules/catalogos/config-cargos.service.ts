import { Injectable } from '@nestjs/common';
@Injectable()
export class ConfigCargosService {
  calcularCargos(subtotal: number): number { return 0; }
  calcular(subtotal: number): number { return this.calcularCargos(subtotal); }
  obtenerCargos(subtotal: number): number { return this.calcularCargos(subtotal); }
  getCargos(subtotal: number): number { return this.calcularCargos(subtotal); }
}
