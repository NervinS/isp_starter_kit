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
exports.JobsService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("typeorm");
let JobsService = class JobsService {
    constructor(ds) {
        this.ds = ds;
    }
    async simular(tipo, fechaISO) {
        const fecha = fechaISO ? new Date(fechaISO) : new Date();
        const usuarios = await this.ds.query(`SELECT id FROM usuarios ORDER BY id LIMIT 5`);
        const detalle = [];
        for (const u of usuarios) {
            const r = await this.ds.transaction('READ COMMITTED', async (em) => {
                const code = `${tipo}-${Math.floor(Date.now() / 1000)}`;
                const [ins] = await em.query(`INSERT INTO ordenes (id, codigo, estado, tecnico_id, tipo, subtotal, total, usuario_id, created_at, updated_at)
           VALUES (uuid_generate_v4(), $1, 'agendada', NULL, $2, 0, 0, $3, now(), now())
           RETURNING id, codigo`, [code, tipo, u.id]);
                await em.query(`UPDATE ordenes SET cerrada_at=NOW(), estado='cerrada' WHERE id=$1 AND cerrada_at IS NULL`, [ins.id]);
                const nuevo = tipo === 'COR' ? 'desconectado'
                    : tipo === 'REC' ? 'instalado'
                        : null;
                if (nuevo) {
                    await em.query(`UPDATE usuarios SET estado=$2 WHERE id=$1`, [u.id, nuevo]);
                }
                return { codigo: ins.codigo, tipo, usuarioId: u.id };
            });
            detalle.push(r);
        }
        return { ok: true, tipo, fecha: fecha.toISOString(), creadas: detalle.length, detalle };
    }
};
exports.JobsService = JobsService;
exports.JobsService = JobsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [typeorm_1.DataSource])
], JobsService);
//# sourceMappingURL=jobs.service.js.map