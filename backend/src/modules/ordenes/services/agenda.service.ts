// src/modules/ordenes/services/agenda.service.ts
import { Injectable, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Injectable()
export class AgendaService {
  constructor(private readonly dataSource: DataSource) {}

  async asignar({ codigo, tecnicoId, fecha, turno }: { codigo: string; tecnicoId: string; fecha: string; turno: string; }) {
    return this.dataSource.transaction(async (m) => {
      const orden = await m.query(`SELECT id, estado FROM ordenes WHERE codigo=$1 FOR UPDATE`, [codigo]);
      if (!orden?.[0]) throw new NotFoundException('Orden no existe');

      await m.query(
        `UPDATE ordenes SET tecnico_id=$1, agenda_fecha=$2, agenda_turno=$3 WHERE codigo=$4`,
        [tecnicoId, fecha, turno, codigo],
      );
      return { codigo, tecnicoId, fecha, turno, estado: 'agendada' };
    });
  }

  async actualizar({ codigo, tecnicoId, fecha, turno }: { codigo: string; tecnicoId?: string|null; fecha?: string|null; turno?: string|null; }) {
    return this.dataSource.transaction(async (m) => {
      const orden = await m.query(`SELECT id FROM ordenes WHERE codigo=$1 FOR UPDATE`, [codigo]);
      if (!orden?.[0]) throw new NotFoundException('Orden no existe');

      const res = await m.query(
        `UPDATE ordenes SET tecnico_id=COALESCE($1, tecnico_id),
                             agenda_fecha=COALESCE($2, agenda_fecha),
                             agenda_turno=COALESCE($3, agenda_turno)
         WHERE codigo=$4`,
        [tecnicoId ?? null, fecha ?? null, turno ?? null, codigo],
      );
      return { codigo, tecnicoId: tecnicoId ?? undefined, fecha: fecha ?? undefined, turno: turno ?? undefined };
    });
  }

  async cancelar({ codigo }: { codigo: string; }) {
    return this.dataSource.transaction(async (m) => {
      const orden = await m.query(`SELECT id FROM ordenes WHERE codigo=$1 FOR UPDATE`, [codigo]);
      if (!orden?.[0]) throw new NotFoundException('Orden no existe');

      await m.query(
        `UPDATE ordenes SET agenda_fecha=NULL, agenda_turno=NULL WHERE codigo=$1`,
        [codigo],
      );
      return { codigo, estado: 'agenda_cancelada' };
    });
  }
}
