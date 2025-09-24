'use client';

import React, { useEffect, useMemo, useState } from 'react';
import SignaturePad from '@/components/SignaturePad'; // usa tu componente existente

type SearchParams = { readonly?: string };

type Tecnico = { codigo?: string | null };
type Cliente = { nombre?: string | null; documento?: string | null; telefono?: string | null; direccion?: string | null; barrio?: string | null; };
type Orden = {
  id: string;
  codigo: string;
  estado: 'creada' | 'agendada' | 'cerrada';
  tecnico?: Tecnico | null;
  cliente?: Cliente | null;
  // …otros campos
};

const API = '/api';

export default function OrdenDetalle({
  params,
  searchParams,
}: {
  params: { codigo: string };
  searchParams: SearchParams;
}) {
  const readonlyQP = searchParams?.readonly === '1';
  const [orden, setOrden] = useState<Orden | null>(null);
  const [loading, setLoading] = useState(false);

  const closed = orden?.estado === 'cerrada';
  const readOnly = closed || readonlyQP;

  async function cargar() {
    setLoading(true);
    try {
      const url = new URL(`${API}/ordenes`, location.origin);
      url.searchParams.set('codigo', params.codigo);
      const r = await fetch(url.toString(), { cache: 'no-store' });
      const list = r.ok ? await r.json() : [];
      setOrden(list?.[0] || null);
    } finally { setLoading(false); }
  }

  useEffect(() => { cargar(); }, []);

  // … tu resto de lógica de cierre, materiales, gps, etc.
  // asegúrate de respetar `readOnly` en inputs/botones

  return (
    <div className="min-h-screen bg-slate-100 p-6">
      <div className="mx-auto max-w-6xl">
        <div className="flex items-center justify-between gap-3">
          <h1 className="text-3xl font-extrabold text-slate-900">Cerrar orden</h1>
          <a href="/tecnico" className="text-blue-700 hover:underline">← Volver al listado</a>
        </div>

        {/* Datos del usuario */}
        <div className="grid md:grid-cols-2 gap-5 mt-6">
          <section className="bg-white rounded-2xl p-4 border border-slate-200 shadow-sm">
            <div className="font-bold text-slate-700 mb-2">Datos del usuario (informativo)</div>
            <div className="grid gap-3">
              <div className="grid grid-cols-2 gap-3">
                <input className="input" value={orden?.cliente?.nombre || ''} disabled />
                <input className="input" value={orden?.cliente?.documento || ''} disabled />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <input className="input" value={orden?.cliente?.telefono || ''} disabled />
                <input className="input" value={orden?.cliente?.direccion || ''} disabled />
              </div>
            </div>
          </section>

          {/* Evidencias / Firma */}
          <section className="bg-white rounded-2xl p-4 border border-slate-200 shadow-sm">
            <div className="font-bold text-slate-700 mb-2">Evidencias</div>
            {/* … tus inputs de fotos, respetando readOnly */}
            <div className="mt-4 font-semibold text-slate-600 mb-1">Firma del cliente</div>
            <SignaturePad onChange={() => {}} height={180} disabled={readOnly} />
            <div className="text-xs text-slate-500">Firme dentro del recuadro</div>
          </section>
        </div>

        {/* … resto de secciones (Datos generales, Materiales, Finalizar) aplicando `disabled={readOnly}` y ocultando botón Cerrar si readOnly */}

        {!readOnly && (
          <div className="mt-6 flex justify-end">
            <button className="px-5 py-2 rounded-xl bg-blue-600 text-white shadow hover:bg-blue-700">
              Cerrar orden
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

/* util tailwind */
declare global {
  namespace JSX {
    interface IntrinsicElements {
      input: React.DetailedHTMLProps<React.InputHTMLAttributes<HTMLInputElement>, HTMLInputElement> & { className?: string }
    }
  }
}
