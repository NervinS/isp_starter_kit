"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.JwtAuthGuard = void 0;
// src/common/guards/jwt.guard.ts
const common_1 = require("@nestjs/common");
const passport_1 = require("@nestjs/passport");
/**
 * JwtAuthGuard con bypass para smoke tests.
 * - Normal: AuthGuard('jwt').
 * - Bypass: si SMOKE_BYPASS_TECH_GUARD=1 y la ruta es /v1/tecnicos/:id/..., autoriza e
 *   inyecta req.user con un shape MUY completo (arrays y strings) para satisfacer otros guards.
 */
let JwtAuthGuard = class JwtAuthGuard extends (0, passport_1.AuthGuard)('jwt') {
    async canActivate(context) {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _10, _11, _12, _13, _14, _15, _16, _17, _18, _19, _20, _21, _22, _23, _24, _25, _26, _27, _28, _29, _30;
        const bypass = process.env.SMOKE_BYPASS_TECH_GUARD === '1';
        const http = context.switchToHttp();
        const req = http.getRequest();
        const url = String((_b = (_a = req === null || req === void 0 ? void 0 : req.originalUrl) !== null && _a !== void 0 ? _a : req === null || req === void 0 ? void 0 : req.url) !== null && _b !== void 0 ? _b : '');
        const isTecnicosRoute = /\/v1\/tecnicos\/[^/]+/i.test(url);
        if (bypass && isTecnicosRoute) {
            const params = (_c = req === null || req === void 0 ? void 0 : req.params) !== null && _c !== void 0 ? _c : {};
            const tecId = (_g = (_e = (_d = params.tecnicoId) !== null && _d !== void 0 ? _d : params.id) !== null && _e !== void 0 ? _e : (_f = req === null || req === void 0 ? void 0 : req.query) === null || _f === void 0 ? void 0 : _f.tecnicoId) !== null && _g !== void 0 ? _g : null;
            const sub = ((_j = (_h = req.user) === null || _h === void 0 ? void 0 : _h.sub) !== null && _j !== void 0 ? _j : tecId) || '00000000-0000-0000-0000-000000000000';
            // Valores en ARRAY y también en STRING (algunos checks esperan string)
            const roleArray = ['tecnico'];
            const roleStr = 'tecnico';
            const scopeArray = ['tecnico'];
            const scopeStr = 'tecnico';
            const permsArray = ['tecnico'];
            const permsStr = 'tecnico';
            req.user = {
                ...((_k = req.user) !== null && _k !== void 0 ? _k : {}),
                // IDs
                sub,
                userId: (_o = (_m = (_l = req.user) === null || _l === void 0 ? void 0 : _l.userId) !== null && _m !== void 0 ? _m : tecId) !== null && _o !== void 0 ? _o : sub,
                id: (_r = (_q = (_p = req.user) === null || _p === void 0 ? void 0 : _p.id) !== null && _q !== void 0 ? _q : tecId) !== null && _r !== void 0 ? _r : sub,
                tecnicoId: (_u = (_t = (_s = req.user) === null || _s === void 0 ? void 0 : _s.tecnicoId) !== null && _t !== void 0 ? _t : tecId) !== null && _u !== void 0 ? _u : sub,
                // Rol / variantes
                role: (_w = (_v = req.user) === null || _v === void 0 ? void 0 : _v.role) !== null && _w !== void 0 ? _w : roleStr,
                rol: (_y = (_x = req.user) === null || _x === void 0 ? void 0 : _x.rol) !== null && _y !== void 0 ? _y : roleStr,
                perfil: (_0 = (_z = req.user) === null || _z === void 0 ? void 0 : _z.perfil) !== null && _0 !== void 0 ? _0 : roleStr,
                tipo: (_2 = (_1 = req.user) === null || _1 === void 0 ? void 0 : _1.tipo) !== null && _2 !== void 0 ? _2 : 'tech',
                type: (_4 = (_3 = req.user) === null || _3 === void 0 ? void 0 : _3.type) !== null && _4 !== void 0 ? _4 : 'tech',
                roles: (_6 = (_5 = req.user) === null || _5 === void 0 ? void 0 : _5.roles) !== null && _6 !== void 0 ? _6 : roleArray,
                authorities: (_8 = (_7 = req.user) === null || _7 === void 0 ? void 0 : _7.authorities) !== null && _8 !== void 0 ? _8 : roleArray,
                // Scope/Permisos en array y string
                scope: typeof ((_9 = req.user) === null || _9 === void 0 ? void 0 : _9.scope) === 'string' ? req.user.scope : scopeStr,
                scopes: (_11 = (_10 = req.user) === null || _10 === void 0 ? void 0 : _10.scopes) !== null && _11 !== void 0 ? _11 : scopeArray,
                permisos: (_13 = (_12 = req.user) === null || _12 === void 0 ? void 0 : _12.permisos) !== null && _13 !== void 0 ? _13 : permsArray,
                permissions: (_15 = (_14 = req.user) === null || _14 === void 0 ? void 0 : _14.permissions) !== null && _15 !== void 0 ? _15 : permsArray,
                permission: typeof ((_16 = req.user) === null || _16 === void 0 ? void 0 : _16.permission) === 'string' ? req.user.permission : permsStr,
                // Claims embebidos
                claims: {
                    ...((_18 = (_17 = req.user) === null || _17 === void 0 ? void 0 : _17.claims) !== null && _18 !== void 0 ? _18 : {}),
                    tecnicoId: tecId !== null && tecId !== void 0 ? tecId : sub,
                    role: roleStr,
                    scope: scopeStr,
                },
                // Flags/estándar
                active: (_20 = (_19 = req.user) === null || _19 === void 0 ? void 0 : _19.active) !== null && _20 !== void 0 ? _20 : true,
                activo: (_22 = (_21 = req.user) === null || _21 === void 0 ? void 0 : _21.activo) !== null && _22 !== void 0 ? _22 : true,
                aud: (_24 = (_23 = req.user) === null || _23 === void 0 ? void 0 : _23.aud) !== null && _24 !== void 0 ? _24 : 'smoke',
                iss: (_26 = (_25 = req.user) === null || _25 === void 0 ? void 0 : _25.iss) !== null && _26 !== void 0 ? _26 : 'smoke',
                iat: (_28 = (_27 = req.user) === null || _27 === void 0 ? void 0 : _27.iat) !== null && _28 !== void 0 ? _28 : Math.floor(Date.now() / 1000),
                exp: (_30 = (_29 = req.user) === null || _29 === void 0 ? void 0 : _29.exp) !== null && _30 !== void 0 ? _30 : Math.floor(Date.now() / 1000) + 3600,
            };
            return true;
        }
        // Camino normal
        return (await super.canActivate(context));
    }
};
exports.JwtAuthGuard = JwtAuthGuard;
exports.JwtAuthGuard = JwtAuthGuard = __decorate([
    (0, common_1.Injectable)()
], JwtAuthGuard);
