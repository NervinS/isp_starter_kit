"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.TecnicosModule = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const tecnicos_controller_1 = require("./tecnicos.controller");
const tecnicos_service_1 = require("./tecnicos.service");
const orden_entity_1 = require("../ordenes/orden.entity");
const orden_material_entity_1 = require("../materiales/orden-material.entity");
const jwt_guard_1 = require("../../common/guards/jwt.guard");
const tech_smoke_bypass_guard_1 = require("../../common/guards/tech-smoke-bypass.guard");
let TecnicosModule = class TecnicosModule {
};
exports.TecnicosModule = TecnicosModule;
exports.TecnicosModule = TecnicosModule = __decorate([
    (0, common_1.Module)({
        imports: [
            typeorm_1.TypeOrmModule.forFeature([orden_entity_1.Orden, orden_material_entity_1.OrdenMaterial])
        ],
        controllers: [tecnicos_controller_1.TecnicosController],
        providers: [
            tecnicos_service_1.TecnicosService,
            tech_smoke_bypass_guard_1.TechSmokeBypassGuard,
            {
                provide: jwt_guard_1.JwtAuthGuard,
                useClass: tech_smoke_bypass_guard_1.TechSmokeBypassGuard,
            }
        ],
        exports: [tecnicos_service_1.TecnicosService]
    })
], TecnicosModule);
//# sourceMappingURL=tecnicos.module.js.map