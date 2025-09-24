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
exports.Orden = void 0;
// src/modules/ordenes/entities/orden.entity.ts
const typeorm_1 = require("typeorm");
const orden_material_entity_1 = require("./orden-material.entity");
let Orden = class Orden {
};
exports.Orden = Orden;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)('uuid'),
    __metadata("design:type", String)
], Orden.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', unique: true }),
    __metadata("design:type", String)
], Orden.prototype, "codigo", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', default: 'agendada' }),
    __metadata("design:type", String)
], Orden.prototype, "estado", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'numeric', precision: 12, scale: 2, default: 0 }),
    __metadata("design:type", String)
], Orden.prototype, "subtotal", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'numeric', precision: 12, scale: 2, default: 0 }),
    __metadata("design:type", String)
], Orden.prototype, "total", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'cerrada_at', type: 'timestamptz', nullable: true }),
    __metadata("design:type", Date)
], Orden.prototype, "cerradaAt", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'tecnico_id', type: 'uuid', nullable: true }),
    __metadata("design:type", String)
], Orden.prototype, "tecnicoId", void 0);
__decorate([
    (0, typeorm_1.CreateDateColumn)({ name: 'created_at', type: 'timestamptz' }),
    __metadata("design:type", Date)
], Orden.prototype, "createdAt", void 0);
__decorate([
    (0, typeorm_1.UpdateDateColumn)({ name: 'updated_at', type: 'timestamptz' }),
    __metadata("design:type", Date)
], Orden.prototype, "updatedAt", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'iniciada_at', type: 'timestamptz', nullable: true }),
    __metadata("design:type", Date)
], Orden.prototype, "iniciadaAt", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'firma_key', type: 'text', nullable: true }),
    __metadata("design:type", String)
], Orden.prototype, "firmaKey", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'pdf_url', type: 'text', nullable: true }),
    __metadata("design:type", String)
], Orden.prototype, "pdfUrl", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true }),
    __metadata("design:type", String)
], Orden.prototype, "tipo", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'cliente_snapshot', type: 'jsonb', nullable: true }),
    __metadata("design:type", Object)
], Orden.prototype, "clienteSnapshot", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'servicio_snapshot', type: 'jsonb', nullable: true }),
    __metadata("design:type", Object)
], Orden.prototype, "servicioSnapshot", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'form_data', type: 'jsonb', nullable: true }),
    __metadata("design:type", Object)
], Orden.prototype, "formData", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'auto_agendada', type: 'boolean', default: false }),
    __metadata("design:type", Boolean)
], Orden.prototype, "autoAgendada", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'auto_cerrada', type: 'boolean', default: false }),
    __metadata("design:type", Boolean)
], Orden.prototype, "autoCerrada", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'agendada_at', type: 'timestamptz', nullable: true }),
    __metadata("design:type", Date)
], Orden.prototype, "agendadaAt", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'pdf_key', type: 'text', nullable: true }),
    __metadata("design:type", String)
], Orden.prototype, "pdfKey", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'agendado_para', type: 'date', nullable: true }),
    __metadata("design:type", String)
], Orden.prototype, "agendadoPara", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true }),
    __metadata("design:type", String)
], Orden.prototype, "turno", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true }),
    __metadata("design:type", String)
], Orden.prototype, "observaciones", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'usuario_id', type: 'uuid', nullable: true }),
    __metadata("design:type", String)
], Orden.prototype, "usuarioId", void 0);
__decorate([
    (0, typeorm_1.Column)({ name: 'snapshot_tecnico', type: 'jsonb', default: () => `'{}'::jsonb` }),
    __metadata("design:type", Object)
], Orden.prototype, "snapshotTecnico", void 0);
__decorate([
    (0, typeorm_1.Index)('ux_ordenes_cierre_token', { unique: true, where: 'cierre_token IS NOT NULL' }),
    (0, typeorm_1.Column)({ name: 'cierre_token', type: 'uuid', nullable: true }),
    __metadata("design:type", String)
], Orden.prototype, "cierreToken", void 0);
__decorate([
    (0, typeorm_1.OneToMany)(() => orden_material_entity_1.OrdenMaterial, (om) => om.orden, { cascade: false }),
    __metadata("design:type", Array)
], Orden.prototype, "materiales", void 0);
exports.Orden = Orden = __decorate([
    (0, typeorm_1.Entity)('ordenes'),
    (0, typeorm_1.Index)('ux_ordenes_codigo', ['codigo'], { unique: true })
], Orden);
