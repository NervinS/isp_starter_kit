"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.TechSmokeBypassGuard = void 0;
// src/common/guards/tech-smoke-bypass.guard.ts
const common_1 = require("@nestjs/common");
const passport_1 = require("@nestjs/passport");
let TechSmokeBypassGuard = class TechSmokeBypassGuard extends (0, passport_1.AuthGuard)('jwt') {
    canActivate(ctx) {
        const bypass = process.env.SMOKE_BYPASS_TECH_GUARD === '1';
        if (!bypass) {
            // flujo normal (usa jwt)
            return super.canActivate(ctx);
        }
        const req = ctx.switchToHttp().getRequest();
        const tecnicoId = req.params?.tecnicoId || req.query?.tecnicoId || 'smoke-tecnico';
        // El resto del sistema suele mirar user.sub / role / scope
        req.user = {
            sub: tecnicoId,
            role: 'tecnico',
            rol: 'tecnico',
            scope: ['tecnico'],
            permisos: ['tecnico'],
            tipo: 'tech'
        };
        return true;
    }
};
exports.TechSmokeBypassGuard = TechSmokeBypassGuard;
exports.TechSmokeBypassGuard = TechSmokeBypassGuard = __decorate([
    (0, common_1.Injectable)()
], TechSmokeBypassGuard);
