// frontend/components/ordenes/SelectorTecnico.tsx
'use client';
import { useEffect, useState } from 'react';
import { TecnicosAPI } from '@/lib/api';

export type Tecnico = { id: string; nombre: string; activo: boolean };

export default function SelectorTecnico({
  value,
  onChange,
}: {
  value?: string;
  onChange: (id: string) => void;
}) {
  const [tecnicos, setTecnicos] = useState<Tecnico[]>([]);
  const [cargando, setCargando] = useState(true);

  useEffect(() => {
    TecnicosAPI.listar()
      .then(setTecnicos)
      .finally(() => setCargando(false));
  }, []);

  if (cargando) return <div className="text-gray-500">Cargando técnicos…</div>;

  return (
    <select
      className="w-full rounded-2xl border border-gray-300 bg-white px-3 py-2 shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
      value={value || ''}
      onChange={(e) => onChange(e.target.value)}
    >
      <option value="">— Seleccione técnico —</option>
      {tecnicos.filter(t => t.activo).map((t) => (
        <option key={t.id} value={t.id}>{t.nombre}</option>
      ))}
    </select>
  );
}
