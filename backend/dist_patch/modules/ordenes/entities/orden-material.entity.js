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
Object.defineProperty(exports, "__esModule", { value: true });
exports.OrdenMaterial = void 0;
// src/modules/ordenes/entities/orden-material.entity.ts
const typeorm_1 = require("typeorm");
const orden_entity_1 = require("./orden.entity");
let OrdenMaterial = class OrdenMaterial {
};
exports.OrdenMaterial = OrdenMaterial;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)('uuid'),
    __metadata("design:type", String)
], OrdenMaterial.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'orden_id', type: 'uuid' }),
    __metadata("design:type", String)
], OrdenMaterial.prototype, "ordenId", void 0);
__decorate([
    (0, typeorm_1.ManyToOne)(() => orden_entity_1.Orden, (o) => o.materiales, { onDelete: 'CASCADE' }),
    (0, typeorm_1.JoinColumn)({ name: 'orden_id', referencedColumnName: 'id' }),
    __metadata("design:type", orden_entity_1.Orden)
], OrdenMaterial.prototype, "orden", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'material_id', type: 'int' }),
    __metadata("design:type", Number)
], OrdenMaterial.prototype, "materialId", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'numeric', precision: 12, scale: 3, default: 0 }),
    __metadata("design:type", String)
], OrdenMaterial.prototype, "cantidad", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'precio_unitario', type: 'numeric', precision: 12, scale: 2, default: 0 }),
    __metadata("design:type", String)
], OrdenMaterial.prototype, "precioUnitario", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'total_calculado', type: 'numeric', precision: 14, scale: 2, nullable: true }),
    __metadata("design:type", String)
], OrdenMaterial.prototype, "totalCalculado", void 0);
__decorate([
    (0, typeorm_1.CreateDateColumn)({ name: 'created_at', type: 'timestamptz' }),
    __metadata("design:type", Date)
], OrdenMaterial.prototype, "createdAt", void 0);
__decorate([
    (0, typeorm_1.UpdateDateColumn)({ name: 'updated_at', type: 'timestamptz' }),
    __metadata("design:type", Date)
], OrdenMaterial.prototype, "updatedAt", void 0);
exports.OrdenMaterial = OrdenMaterial = __decorate([
    (0, typeorm_1.Entity)('orden_materiales'),
    (0, typeorm_1.Index)('ux_orden_materiales_orden_mat', ['ordenId', 'materialId'], { unique: true })
], OrdenMaterial);
