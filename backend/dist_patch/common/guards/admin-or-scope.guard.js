"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdminOrScopeGuard = void 0;
// src/common/guards/admin-or-scope.guard.ts
const common_1 = require("@nestjs/common");
/**
 * AdminOrScopeGuard con bypass para smoke tests.
 * - Si SMOKE_BYPASS_TECH_GUARD=1 y la ruta es /v1/tecnicos/:id/..., permite siempre.
 * - Fuera de bypass, aplica una validación mínima: admin o scope/permiso 'tecnico'.
 *
 * Esta versión es segura para smoke tests y no afecta endpoints no-tecnico.
 */
let AdminOrScopeGuard = class AdminOrScopeGuard {
    canActivate(context) {
        var _a, _b, _c;
        const bypass = process.env.SMOKE_BYPASS_TECH_GUARD === '1';
        const req = context.switchToHttp().getRequest();
        const url = String((_b = (_a = req === null || req === void 0 ? void 0 : req.originalUrl) !== null && _a !== void 0 ? _a : req === null || req === void 0 ? void 0 : req.url) !== null && _b !== void 0 ? _b : '');
        const isTecnicosRoute = /\/v1\/tecnicos\/[^/]+/i.test(url);
        if (bypass && isTecnicosRoute)
            return true;
        const user = (_c = req === null || req === void 0 ? void 0 : req.user) !== null && _c !== void 0 ? _c : {};
        const isAdmin = user.role === 'admin' ||
            user.rol === 'admin' ||
            (Array.isArray(user.roles) && user.roles.includes('admin')) ||
            (Array.isArray(user.authorities) && user.authorities.includes('admin')) ||
            user.perfil === 'admin';
        const hasTecnicoScope = user.scope === 'tecnico' ||
            (Array.isArray(user.scope) && user.scope.includes('tecnico')) ||
            (Array.isArray(user.scopes) && user.scopes.includes('tecnico')) ||
            (Array.isArray(user.permissions) && user.permissions.includes('tecnico')) ||
            (Array.isArray(user.permisos) && user.permisos.includes('tecnico')) ||
            user.permission === 'tecnico';
        return !!(isAdmin || hasTecnicoScope);
    }
};
exports.AdminOrScopeGuard = AdminOrScopeGuard;
exports.AdminOrScopeGuard = AdminOrScopeGuard = __decorate([
    (0, common_1.Injectable)()
], AdminOrScopeGuard);
