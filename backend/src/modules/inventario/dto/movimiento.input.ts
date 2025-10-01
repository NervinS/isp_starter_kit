// src/modules/inventario/dto/movimiento.input.ts
import { MovimientoDto, TipoMovimiento } from './movimiento.dto';

/**
 * Tipo de entrada que usa el service y que el controller arma.
 */
export type MovimientoInput = MovimientoDto & {
  tipo: TipoMovimiento;
  tecnicoId?: string;
};
