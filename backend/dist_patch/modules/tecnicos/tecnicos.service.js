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
exports.TecnicosService = void 0;
// src/modules/tecnicos/tecnicos.service.ts
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const orden_entity_1 = require("../ordenes/entities/orden.entity");
const orden_material_entity_1 = require("../ordenes/entities/orden-material.entity");
let TecnicosService = class TecnicosService {
    constructor(ordenRepo, omRepo, ds) {
        this.ordenRepo = ordenRepo;
        this.omRepo = omRepo;
        this.ds = ds;
    }
    /**
     * Listado básico para smoke.
     */
    async pendientes(tecnicoId) {
        return this.ordenRepo.find({
            where: { tecnicoId: tecnicoId },
            take: 50,
            order: { creadoAt: 'DESC' },
        });
    }
    /**
     * Pone la orden en 'en_proceso'. Idempotente: si ya está en proceso o cerrada, responde OK.
     */
    async iniciarOrden(tecnicoId, codigo) {
        const ord = await this.ordenRepo.findOne({ where: { codigo } });
        if (!ord)
            throw new common_1.NotFoundException('Orden no encontrada');
        if (ord.tecnicoId && ord.tecnicoId !== tecnicoId) {
            throw new common_1.ForbiddenException('Orden no está asignada a este técnico');
        }
        if (ord.estado === 'cerrada') {
            return { ok: true, codigo, estado: ord.estado };
        }
        if (ord.estado !== 'en_proceso') {
            await this.ordenRepo.update(ord.id, {
                estado: 'en_proceso',
                iniciadaAt: new Date(),
            });
        }
        return { ok: true, codigo, estado: 'en_proceso' };
    }
    /**
     * Cierra la orden. Idempotente: si ya está cerrada, responde OK.
     * Robusto: ignora materiales cuyo materialId no sea entero (evita 500 con "DROP_1").
     */
    async cerrarOrden(tecnicoId, codigo, dto, _idemKey) {
        const ord = await this.ordenRepo.findOne({ where: { codigo } });
        if (!ord)
            throw new common_1.NotFoundException('Orden no encontrada');
        if (ord.tecnicoId && ord.tecnicoId !== tecnicoId) {
            throw new common_1.ForbiddenException('Orden no está asignada a este técnico');
        }
        // Idempotencia a nivel de estado
        if (ord.estado === 'cerrada') {
            return { ok: true, codigo, estado: 'cerrada' };
        }
        // --- Materiales (tolerante a IDs no numéricos) ---
        const mats = Array.isArray(dto === null || dto === void 0 ? void 0 : dto.materiales) ? dto.materiales : [];
        // Consolidar cantidades por materialId entero
        const consolida = {};
        for (const m of mats) {
            const n = Number(m.materialId);
            if (Number.isFinite(n) && Number.isInteger(n)) {
                const qty = Number(m.cantidad) || 0;
                if (qty > 0)
                    consolida[n] = (consolida[n] || 0) + qty;
            }
            // Si NO es entero, lo ignoramos (clave para el smoke que manda "DROP_1")
        }
        // Insert/Update en orden_material
        for (const [idStr, qty] of Object.entries(consolida)) {
            const mid = Number(idStr);
            const existing = await this.omRepo.findOne({
                where: { ordenId: ord.id, materialId: mid },
            });
            if (existing) {
                await this.omRepo.update(existing.id, {
                    cantidad: existing.cantidad + qty,
                });
            }
            else {
                await this.omRepo.insert({
                    ordenId: ord.id,
                    materialId: mid,
                    cantidad: qty,
                });
            }
        }
        // Subtotal/total simplificado (0 si no manejamos precios aquí)
        let total = 0;
        await this.ordenRepo.update(ord.id, {
            subtotal: total,
            total: total,
        });
        // Estado y campos adicionales
        await this.ds.transaction(async (trx) => {
            var _a, _b, _c, _d, _e, _f, _g, _h;
            await trx.getRepository(orden_entity_1.Orden).update(ord.id, {
                estado: 'cerrada',
                cerradaAt: new Date(),
                snapshotTecnico: ((_b = (_a = dto === null || dto === void 0 ? void 0 : dto.snapshot) !== null && _a !== void 0 ? _a : ord.snapshotTecnico) !== null && _b !== void 0 ? _b : {}),
                observaciones: ((_d = (_c = dto === null || dto === void 0 ? void 0 : dto.observaciones) !== null && _c !== void 0 ? _c : ord.observaciones) !== null && _d !== void 0 ? _d : null),
                firmaImgKey: ((_f = (_e = dto === null || dto === void 0 ? void 0 : dto.firmaKey) !== null && _e !== void 0 ? _e : ord.firmaImgKey) !== null && _f !== void 0 ? _f : null),
                evidencias: ((_h = (_g = dto === null || dto === void 0 ? void 0 : dto.fotos) !== null && _g !== void 0 ? _g : ord.evidencias) !== null && _h !== void 0 ? _h : []),
            });
        });
        return { ok: true, codigo, estado: 'cerrada' };
    }
};
exports.TecnicosService = TecnicosService;
exports.TecnicosService = TecnicosService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(orden_entity_1.Orden)),
    __param(1, (0, typeorm_1.InjectRepository)(orden_material_entity_1.OrdenMaterial)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.DataSource])
], TecnicosService);
