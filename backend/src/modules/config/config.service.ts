// backend/src/modules/config/config.service.ts
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Servicio simple para centralizar cargos/fees de órdenes.
 * Toma valores desde variables de entorno y aplica defaults en 0.
 *
 * .env sugerido:
 *   CARGO_INSTALACION=0
 *   CARGO_RECONTRATACION=0
 *   CARGO_ADICIONAL=0
 */
@Injectable()
export class ConfigCargosService {
  constructor(private readonly cfg: ConfigService) {}

  async obtenerOCrear(): Promise<{
    instalacion: number;
    recontratacion: number;
    cargoAdicional: number;
  }> {
    const instalacion = Number(this.cfg.get('CARGO_INSTALACION') ?? 0);
    const recontratacion = Number(this.cfg.get('CARGO_RECONTRATACION') ?? 0);
    const cargoAdicional = Number(this.cfg.get('CARGO_ADICIONAL') ?? 0);

    return { instalacion, recontratacion, cargoAdicional };
  }
}
