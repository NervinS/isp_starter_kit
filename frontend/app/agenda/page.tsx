'use client';
import React, { useEffect, useMemo, useState } from 'react';

type Cliente = {
  nombre?: string | null;
  documento?: string | null;
  direccion?: string | null;
  barrio?: string | null;
  sector?: string | null;
};
type Tecnico = { id: string; codigo: string; nombre?: string | null; activo?: boolean };
type Orden = {
  id: string;
  codigo: string;
  estado: 'creada' | 'agendada' | 'cerrada';
  tipo?: string | null;
  agendadoPara?: string | null;
  cliente?: Cliente | null;
  tecnico?: { id?: string; codigo?: string | null; nombre?: string | null } | null;
};

const API = '/api';

export default function Agenda() {
  const [q, setQ] = useState('');
  const [tab, setTab] = useState<'creadas' | 'agendadas'>('creadas');

  const [creadas, setCreadas] = useState<Orden[]>([]);
  const [agendadas, setAgendadas] = useState<Orden[]>([]);
  const [tecnicos, setTecnicos] = useState<Tecnico[]>([]);

  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);

  // panel inline de (re)agendamiento
  const [panel, setPanel] = useState<{ codigo: string; modo: 'agendar' | 'reagendar' } | null>(null);
  const [fecha, setFecha] = useState<string>('');
  const [turno, setTurno] = useState<'am' | 'pm'>('am');
  const [tecSel, setTecSel] = useState<string>('');

  const closePanel = () => setPanel(null);

  async function cargar() {
    setLoading(true);
    try {
      // Órdenes creadas
      {
        const u = new URL(`${API}/agenda/ordenes`, location.origin);
        u.searchParams.set('estado', 'creada');
        const r = await fetch(u.toString(), { cache: 'no-store' });
        setCreadas(r.ok ? await r.json() : []);
      }
      // Órdenes agendadas
      {
        const u = new URL(`${API}/agenda/ordenes`, location.origin);
        u.searchParams.set('estado', 'agendada');
        const r = await fetch(u.toString(), { cache: 'no-store' });
        setAgendadas(r.ok ? await r.json() : []);
      }
      // Técnicos (activos)
      {
        const rt = await fetch('/api/tecnicos', { cache: 'no-store' });
        const listT: Tecnico[] = rt.ok ? await rt.json() : [];
        setTecnicos(listT.filter((t) => t.activo !== false));
      }
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    cargar();
  }, []);

  // --------- Helpers visuales/filtrado ----------
  const base = tab === 'creadas' ? creadas : agendadas;

  const filtradas = useMemo(() => {
    const needle = q.trim().toLowerCase();
    if (!needle) return base;
    return base.filter((o) => {
      const nom = (o.cliente?.nombre || '').toLowerCase();
      const doc = (o.cliente?.documento || '').toLowerCase();
      const cod = (o.codigo || '').toLowerCase();
      const tip = (o.tipo || '').toLowerCase();
      return (
        cod.includes(needle) ||
        nom.includes(needle) ||
        doc.includes(needle) ||
        tip.includes(needle)
      );
    });
  }, [q, base]);

  const addr = (c?: Cliente | null) => c?.direccion || '—';
  const barrio = (c?: Cliente | null) => c?.barrio || c?.sector || '—';
  const tec = (o: Orden) => o.tecnico?.codigo || o.tecnico?.nombre || '—';
  const formatDT = (iso?: string | null) => (!iso ? '—' : new Date(iso).toLocaleString());

  // --------- Acciones ----------
  async function enviarAsignacion(codigo: string, modo: 'agendar' | 'reagendar') {
    if (!tecSel || !fecha) return;
    setSaving(true);
    try {
      const body = { fecha, turno, tecnicoCodigo: tecSel };
      const r = await fetch(`${API}/agenda/ordenes/${codigo}/asignar`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (!r.ok) {
        alert(`No se pudo ${modo} la orden (HTTP ${r.status})`);
        return;
      }
      await cargar();
      closePanel();
    } finally {
      setSaving(false);
    }
  }

  async function cancelarOrden(codigo: string) {
    const ok = window.confirm(`¿Cancelar la orden ${codigo}? Esta acción no se puede deshacer.`);
    if (!ok) return;
    setSaving(true);
    try {
      // ⬇️ Si tu backend usa otra ruta (p. ej. /api/ordenes/:codigo/cancelar), cámbiala aquí:
      const r = await fetch(`${API}/agenda/ordenes/${codigo}/cancelar`, { method: 'POST' });
      if (!r.ok) {
        alert(`No se pudo cancelar (HTTP ${r.status}).`);
        return;
      }
      await cargar();
    } finally {
      setSaving(false);
    }
  }

  // --------- UI ----------
  return (
    <div className="min-h-screen bg-[#F5F5F5]">
      <div className="mx-auto max-w-7xl px-6 py-6">
        {/* Header */}
        <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h1 className="text-3xl font-extrabold text-slate-900">Agenda</h1>
            <p className="text-sm text-slate-500 mt-1">
              Gestiona órdenes <b>CREADAS</b> (agendar/cancelar) y <b>AGENDADAS</b> (reagendar).
            </p>
          </div>
          <div className="flex items-center gap-2">
            <a
              href="/tecnico"
              className="rounded-xl bg-white border border-slate-200 px-3 py-2 text-sm text-slate-800 shadow-sm hover:bg-slate-50"
            >
              Ver técnico
            </a>
            <a
              href="/ordenes"
              className="rounded-xl bg-[#007BFF] text-white px-3 py-2 text-sm shadow hover:bg-[#0168d6]"
            >
              Crear orden
            </a>
          </div>
        </div>

        {/* Toolbar */}
        <div className="mt-5 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div className="flex gap-2">
            <button
              onClick={() => setTab('creadas')}
              className={`px-4 py-2 rounded-xl border text-sm shadow-sm transition ${
                tab === 'creadas'
                  ? 'bg-[#E9F2FF] border-[#B6D3FF] text-[#0B5ED7]'
                  : 'bg-white border-slate-200 text-slate-700 hover:bg-slate-50'
              }`}
            >
              Creadas
              <span className="ml-2 inline-flex items-center justify-center rounded-full bg-white border border-current px-2 text-xs">
                {creadas.length}
              </span>
            </button>
            <button
              onClick={() => setTab('agendadas')}
              className={`px-4 py-2 rounded-xl border text-sm shadow-sm transition ${
                tab === 'agendadas'
                  ? 'bg-[#E9F2FF] border-[#B6D3FF] text-[#0B5ED7]'
                  : 'bg-white border-slate-200 text-slate-700 hover:bg-slate-50'
              }`}
            >
              Agendadas
              <span className="ml-2 inline-flex items-center justify-center rounded-full bg-white border border-current px-2 text-xs">
                {agendadas.length}
              </span>
            </button>
          </div>

          <div className="w-full md:w-[520px]">
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Buscar por código, nombre o documento…"
              className="w-full bg-white rounded-xl px-3 py-2 text-sm border border-slate-200 shadow-sm outline-none focus:ring-2 focus:ring-[#007BFF]/30"
            />
          </div>
        </div>

        {/* Listado */}
        <div className="mt-6 grid md:grid-cols-2 gap-5">
          {loading && (
            <div className="text-slate-500 text-sm">Cargando…</div>
          )}

          {!loading && filtradas.length === 0 && (
            <div className="text-slate-500 text-sm">
              No hay órdenes {tab}.
            </div>
          )}

          {filtradas.map((o) => (
            <div
              key={o.id}
              className="bg-white rounded-2xl p-4 border border-slate-200 shadow-sm"
            >
              {/* Encabezado */}
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <div className="text-xs text-slate-500">Código</div>
                  <div className="font-semibold text-slate-800 truncate">{o.codigo}</div>
                </div>
                <span
                  className={`px-2 py-1 rounded-full text-xs font-semibold ring-1 ${
                    o.estado === 'creada'
                      ? 'bg-amber-50 text-amber-700 ring-amber-200'
                      : o.estado === 'agendada'
                      ? 'bg-blue-50 text-blue-700 ring-blue-200'
                      : 'bg-emerald-50 text-emerald-700 ring-emerald-200'
                  }`}
                >
                  {o.estado.toUpperCase()}
                </span>
              </div>

              {/* Detalle */}
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
                  <div className="text-xs text-slate-500">DOCUMENTO</div>
                  <div className="mt-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm">
                    {o.cliente?.documento || '—'}
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

                <div>
                  <div className="text-xs text-slate-500">TÉCNICO</div>
                  <div className="mt-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm">
                    {tec(o)}
                  </div>
                </div>
              </div>

              {/* Acciones */}
              <div className="mt-4 flex flex-wrap items-center gap-2">
                {o.estado === 'creada' && (
                  <>
                    <button
                      onClick={() => {
                        setPanel({ codigo: o.codigo, modo: 'agendar' });
                        setTecSel('');
                        setFecha('');
                        setTurno('am');
                      }}
                      className="px-4 py-2 rounded-xl bg-[#007BFF] text-white shadow hover:bg-[#0168d6]"
                    >
                      Agendar
                    </button>

                    <button
                      onClick={() => cancelarOrden(o.codigo)}
                      disabled={saving}
                      className="px-4 py-2 rounded-xl bg-white text-[#B42318] border border-[#F4C7C3] shadow-sm hover:bg-[#FFF1F0]"
                    >
                      Cancelar
                    </button>
                  </>
                )}

                {o.estado === 'agendada' && (
                  <button
                    onClick={() => {
                      setPanel({ codigo: o.codigo, modo: 'reagendar' });
                      setTecSel(o.tecnico?.codigo || '');
                      setFecha('');
                      setTurno('am');
                    }}
                    className="px-4 py-2 rounded-xl bg-amber-600 text-white shadow hover:bg-amber-700"
                  >
                    Reagendar
                  </button>
                )}

                <a
                  href={`/tecnico/${o.codigo}?readonly=1`}
                  className="px-4 py-2 rounded-xl border border-slate-200 bg-white text-slate-800 hover:bg-slate-50"
                >
                  Ver
                </a>
              </div>

              {/* Panel inline de agendamiento */}
              {panel?.codigo === o.codigo && (
                <div className="mt-4 rounded-xl border border-slate-200 bg-slate-50 p-3">
                  <div className="text-sm font-semibold text-slate-700 mb-2">
                    {panel.modo === 'agendar' ? 'Agendar orden' : 'Reagendar orden'}
                  </div>
                  <div className="grid sm:grid-cols-3 gap-3">
                    <input
                      type="datetime-local"
                      value={fecha}
                      onChange={(e) => setFecha(e.target.value)}
                      className="bg-white rounded-lg px-3 py-2 text-sm border border-slate-200"
                    />
                    <select
                      value={turno}
                      onChange={(e) => setTurno(e.target.value as 'am' | 'pm')}
                      className="bg-white rounded-lg px-3 py-2 text-sm border border-slate-200"
                    >
                      <option value="am">AM</option>
                      <option value="pm">PM</option>
                    </select>
                    <select
                      value={tecSel}
                      onChange={(e) => setTecSel(e.target.value)}
                      className="bg-white rounded-lg px-3 py-2 text-sm border border-slate-200"
                    >
                      <option value="">Técnico…</option>
                      {tecnicos.map((t) => (
                        <option key={t.id} value={t.codigo}>
                          {t.codigo} {t.nombre ? `— ${t.nombre}` : ''}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="mt-3 flex items-center gap-2">
                    <button
                      disabled={!tecSel || !fecha || saving}
                      onClick={() => enviarAsignacion(o.codigo, panel.modo)}
                      className="px-4 py-2 rounded-xl bg-[#007BFF] text-white shadow hover:bg-[#0168d6] disabled:opacity-60"
                    >
                      {saving ? 'Guardando…' : panel.modo === 'agendar' ? 'Agendar' : 'Reagendar'}
                    </button>
                    <button
                      onClick={closePanel}
                      className="px-4 py-2 rounded-xl border border-slate-200 bg-white text-slate-800 hover:bg-slate-50"
                    >
                      Cerrar
                    </button>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
