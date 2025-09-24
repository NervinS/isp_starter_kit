"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.TecnicosController = void 0;
const common_1 = require("@nestjs/common");
const tecnicos_service_1 = require("./tecnicos.service");
let TecnicosController = class TecnicosController {
    constructor(svc) {
        this.svc = svc;
    }
    async pendientes(tecnicoId, auth) {
        var _a;
        const payload = this.svc.decodeJwt(auth);
        if (!payload || payload.role !== 'TECH') {
            throw new common_1.ForbiddenException('Token inválido para técnico');
        }
        const claimId = (_a = payload.tecId) !== null && _a !== void 0 ? _a : payload.sub;
        if (claimId !== tecnicoId) {
            throw new common_1.ForbiddenException('Token no corresponde a este técnico');
        }
        return this.svc.pendientes(tecnicoId);
    }
    async iniciar(tecnicoId, codigo, auth) {
        var _a;
        const payload = this.svc.decodeJwt(auth);
        if (!payload || payload.role !== 'TECH') {
            throw new common_1.ForbiddenException('Token inválido para técnico');
        }
        const claimId = (_a = payload.tecId) !== null && _a !== void 0 ? _a : payload.sub;
        if (claimId !== tecnicoId) {
            throw new common_1.ForbiddenException('Token no corresponde a este técnico');
        }
        return this.svc.iniciarOrden(tecnicoId, codigo);
    }
    async cerrar(tecnicoId, codigo, dto = {}, auth) {
        var _a;
        const payload = this.svc.decodeJwt(auth);
        if (!payload || payload.role !== 'TECH') {
            throw new common_1.ForbiddenException('Token inválido para técnico');
        }
        const claimId = (_a = payload.tecId) !== null && _a !== void 0 ? _a : payload.sub;
        if (claimId !== tecnicoId) {
            throw new common_1.ForbiddenException('Token no corresponde a este técnico');
        }
        return this.svc.cerrarOrden(tecnicoId, codigo, dto);
    }
};
exports.TecnicosController = TecnicosController;
__decorate([
    (0, common_1.Get)(':tecnicoId/pendientes'),
    __param(0, (0, common_1.Param)('tecnicoId')),
    __param(1, (0, common_1.Headers)('authorization')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", Promise)
], TecnicosController.prototype, "pendientes", null);
__decorate([
    (0, common_1.Post)(':tecnicoId/ordenes/:codigo/iniciar'),
    (0, common_1.HttpCode)(200),
    __param(0, (0, common_1.Param)('tecnicoId')),
    __param(1, (0, common_1.Param)('codigo')),
    __param(2, (0, common_1.Headers)('authorization')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String]),
    __metadata("design:returntype", Promise)
], TecnicosController.prototype, "iniciar", null);
__decorate([
    (0, common_1.Post)(':tecnicoId/ordenes/:codigo/cerrar'),
    (0, common_1.HttpCode)(200),
    __param(0, (0, common_1.Param)('tecnicoId')),
    __param(1, (0, common_1.Param)('codigo')),
    __param(2, (0, common_1.Body)()),
    __param(3, (0, common_1.Headers)('authorization')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, Object, String]),
    __metadata("design:returntype", Promise)
], TecnicosController.prototype, "cerrar", null);
exports.TecnicosController = TecnicosController = __decorate([
    (0, common_1.Controller)('tecnicos'),
    __metadata("design:paramtypes", [tecnicos_service_1.TecnicosService])
], TecnicosController);
//# sourceMappingURL=tecnicos.controller.js.map