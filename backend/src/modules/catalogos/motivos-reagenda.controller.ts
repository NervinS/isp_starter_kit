// src/modules/catalogos/motivos-reagenda.controller.ts

/**
 * Este archivo sirve como puente para mantener compatibilidad con los imports
 * existentes en CatalogosModule. Re-exporta los controladores públicos reales
 * definidos en `motivos-reagenda.public.controller.ts` y conserva un stub
 * legacy sin rutas.
 */

export {
  MotivosReagendaPublicControllerKebab,
  MotivosReagendaPublicControllerUnderscore,
} from './motivos-reagenda.public.controller';

import { Controller } from '@nestjs/common';

/**
 * Controlador legacy sin endpoints.
 * Se deja para compatibilidad con referencias antiguas.
 * No define rutas efectivas.
 */
@Controller('_deprecated/motivos-reagenda')
export class MotivosReagendaController {}
