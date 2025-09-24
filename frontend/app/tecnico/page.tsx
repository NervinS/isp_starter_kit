'use client';

import React, { useEffect, useMemo, useState } from 'react';

type Cliente = {
  nombre?: string | null;
  documento?: string | null;
  telefono?: string | null;
  direccion?: string | null;
  barrio?: string | null;           // si el backend lo envía
  sector?: string | null;           // fallback común en algunas BD
};
type Tecnico = { id?: string; codigo?: string | null; nombre?: string | null } | null;

type Orden = {
  id: string;
  codigo: string;
  estado: 'creada' | 'agendada' | 'cerrada';
  tipo?: string | null;
  agendadoPara?: string | null;
  cliente?: Cliente | null;
  tecnico?: Tecnico | null;
};

const API = '/api';

const ESTADOS = ['pendientes', 'creada', 'agendada', 'cerrada', 'todas'] as const;
type Tab = typeof ESTADOS[number];

export default function TecnicoPendientes() {
  const [tab, setTab] = useState<Tab>('pendientes');
  const [q, setQ] = useState('');
  const [loading, setLoading] = useState(false);
  const [items, setItems] = useState<Orden[]>([]);

  async function cargar() {
    setLoading(true);
    try {
      const url = new URL(`${API}/ordenes`, location.origin);
      if (tab !== 'todas') url.searchParams.set('estado', tab);
      const r = await fetch(url.toString(), { cache: 'no-store' });
      const data: Orden[] = r.ok ? await r.json() : [];
      setItems(data);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { cargar(); }, [tab]);

  const view = useMemo(() => {
    const needle = q.trim().toLowerCase();
    if (!needle) return items;
    return items.filter((o) => {
      const hay =
        o.codigo?.toLowerCase().includes(needle) ||
        o.tipo?.toLowerCase().includes(needle) ||
        (o.cliente?.nombre?.toLowerCase() || '').includes(needle) ||
        (o.cliente?.documento || '').toLowerCase().includes(needle);
      return !!hay;
    });
  }, [items, q]);

  function badgeColor(estado: Orden['estado']) {
    if (estado === 'creada') return 'bg-amber-50 text-amber-700 ring-1 ring-amber-200';
    if (estado === 'agendada') return 'bg-blue-50 text-blue-700 ring-1 ring-blue-200';
    return 'bg-slate-100 text-slate-600 ring-1 ring-slate-200';
  }

  const formatDT = (iso?: string | null) => {
    if (!iso) return '—';
    try { return new Date(iso).toLocaleString(); } catch { return iso; }
  };

  const addr = (c?: Cliente | null) => c?.direccion || '—';
  const barrio = (c?: Cliente | null) => c?.barrio || c?.sector || '—';
  const tec = (t?: Tecnico | null) => t?.codigo || t?.nombre || '—';

  return (
    <div className="min-h-screen bg-slate-100 p-6">
      <div className="mx-auto max-w-6xl">
        <div className="flex items-center justify-between gap-3">
          <h1 className="text-3xl font-extrabold text-slate-900">Órdenes pendientes</h1>
          <button
            onClick={cargar}
            className="px-4 py-2 rounded-xl bg-blue-600 text-white shadow hover:bg-blue-700"
          >
            Recargar
          </button>
        </div>
        <p className="text-sm text-slate-500 mt-1">Tareas asignadas listas para atender.</p>

        <div className="mt-4 flex items-center gap-3 flex-wrap">
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por código, cliente o tipo..."
            className="w-full md:w-[520px] bg-white rounded-xl px-3 py-2 text-sm border border-slate-200 shadow-sm"
          />
          <div className="flex items-center gap-2">
            {ESTADOS.map((t) => (
              <button
                key={t}
                onClick={() => setTab(t)}
                className={`px-3 py-1 rounded-full border text-sm ${
                  tab === t
                    ? 'border-blue-300 bg-blue-50 text-blue-700'
                    : 'border-slate-200 bg-white text-slate-700 hover:bg-slate-50'
                }`}
              >
                {t[0].toUpperCase() + t.slice(1)}
              </button>
            ))}
          </div>
        </div>

        {/* LISTA */}
        <div className="mt-6 grid md:grid-cols-2 gap-5">
          {loading && (
            <div className="text-slate-500 text-sm">Cargando…</div>
          )}

          {!loading && view.length === 0 && (
            <div className="text-slate-500 text-sm">Sin órdenes por ahora.</div>
          )}

          {view.map((o) => (
            <div key={o.id} className="bg-white rounded-2xl p-4 border border-slate-200 shadow-sm">
              <div className="flex items-center justify-between">
                <div className="text-slate-800 font-semibold">
                  <div className="text-xs text-slate-500">Código</div>
                  <div>{o.codigo}</div>
                </div>
                <span className={`px-2 py-1 rounded-full text-xs font-semibold ${badgeColor(o.estado)}`}>
                  {o.estado.toUpperCase()}
                </span>
              </div>

              <div className="grid sm:grid-cols-2 gap-3 mt-3">
                <div>
                  <div className="text-xs text-slate-500">TIPO</div>
                  <div className="mt-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm">
                    {o.tipo || '—'}
                  </div>
                </div>
                <div>
                  <div className="text-xs text-slate-500">AGENDADO PARA</div>
                  <div className="mt-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm">
                    {formatDT(o.agendadoPara)}
                  </div>
                </div>
                <div>
                  <div className="text-xs text-slate-500">CLIENTE</div>
                  <div className="mt-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm">
                    {o.cliente?.nombre || '—'}
                  </div>
                </div>
                <div>
                  <div className="text-xs text-slate-500">TÉCNICO</div>
                  <div className="mt-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm">
                    {tec(o.tecnico)}
                  </div>
                </div>
                <div>
                  <div className="text-xs text-slate-500">DIRECCIÓN</div>
                  <div className="mt-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm">
                    {addr(o.cliente)}
                  </div>
                </div>
                <div>
                  <div className="text-xs text-slate-500">BARRIO</div>
                  <div className="mt-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm">
                    {barrio(o.cliente)}
                  </div>
                </div>
              </div>

              {/* Acciones */}
              {o.estado !== 'cerrada' && (
                <div className="mt-4 flex items-center gap-2">
                  <a
                    href={`/tecnico/${o.codigo}`}
                    className="px-4 py-2 rounded-xl bg-blue-600 text-white shadow hover:bg-blue-700"
                  >
                    Abrir orden
                  </a>
                  <a
                    href={`/tecnico/${o.codigo}?readonly=1`}
                    className="px-4 py-2 rounded-xl border border-slate-200 bg-white text-slate-800 hover:bg-slate-50"
                  >
                    Ver
                  </a>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
