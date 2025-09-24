// frontend/components/ordenes/SelectorMateriales.tsx
'use client';
import { useEffect, useMemo, useState } from 'react';
import { MaterialesAPI } from '@/lib/api';

type Material = { id: string; codigo: string; nombre: string; unidad?: string };

export type LineaMaterial = { materialId: string; cantidad: number; precioUnitario?: number };

export default function SelectorMateriales({
  value,
  onChange,
}: {
  value: LineaMaterial[];
  onChange: (v: LineaMaterial[]) => void;
}) {
  const [materiales, setMateriales] = useState<Material[]>([]);
  const [cargando, setCargando] = useState(true);

  useEffect(() => {
    MaterialesAPI.listar()
      .then(setMateriales)
      .finally(() => setCargando(false));
  }, []);

  const agregarLinea = () => onChange([...(value || []), { materialId: '', cantidad: 1, precioUnitario: 0 }]);
  const eliminarLinea = (idx: number) => onChange(value.filter((_, i) => i !== idx));
  const actualizarLinea = (idx: number, patch: Partial<LineaMaterial>) =>
    onChange(value.map((l, i) => (i === idx ? { ...l, ...patch } : l)));

  const subtotal = useMemo(
    () => (value || []).reduce((acc, l) => acc + (Number(l.precioUnitario || 0) * Number(l.cantidad || 0)), 0),
    [value],
  );

  if (cargando) return <div className="text-gray-500">Cargando materiales…</div>;

  return (
    <div className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold text-gray-800">Materiales utilizados</h3>
        <button onClick={agregarLinea} type="button" className="text-blue-600 hover:underline">+ Agregar</button>
      </div>

      <div className="mt-3 space-y-2">
        {value?.map((l, idx) => (
          <div key={idx} className="grid grid-cols-12 gap-2">
            <select
              className="col-span-5 rounded-xl border border-gray-300 bg-white px-3 py-2"
              value={l.materialId}
              onChange={(e) => actualizarLinea(idx, { materialId: e.target.value })}
            >
              <option value="">— Seleccione material —</option>
              {materiales.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.codigo} — {m.nombre}{m.unidad ? ` (${m.unidad})` : ''}
                </option>
              ))}
            </select>

            <input
              type="number"
              min={1}
              className="col-span-2 rounded-xl border border-gray-300 px-3 py-2"
              value={l.cantidad}
              onChange={(e) => actualizarLinea(idx, { cantidad: Number(e.target.value) })}
              placeholder="Cant."
            />

            <input
              type="number"
              min={0}
              className="col-span-3 rounded-xl border border-gray-300 px-3 py-2"
              value={l.precioUnitario ?? 0}
              onChange={(e) => actualizarLinea(idx, { precioUnitario: Number(e.target.value) })}
              placeholder="Precio unit."
            />

            <button
              type="button"
              onClick={() => eliminarLinea(idx)}
              className="col-span-2 rounded-xl border border-gray-300 px-3 py-2 text-red-600 hover:bg-red-50"
            >
              Eliminar
            </button>
          </div>
        ))}

        {(!value || value.length === 0) && (
          <div className="text-gray-500 text-sm">Sin materiales aún.</div>
        )}
      </div>

      <div className="mt-3 flex justify-end text-sm">
        <div className="rounded-xl bg-gray-50 px-3 py-1">Subtotal: <b>${subtotal.toLocaleString()}</b></div>
      </div>
    </div>
  );
}
