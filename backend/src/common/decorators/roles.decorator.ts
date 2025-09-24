// src/common/decorators/roles.decorator.ts
import { SetMetadata } from '@nestjs/common';
export const ROLES_KEY = 'roles';
export type AppRole = 'admin' | 'tecnico' | 'ventas';
export const Roles = (...roles: AppRole[]) => SetMetadata(ROLES_KEY, roles);
