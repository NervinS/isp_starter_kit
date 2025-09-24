'use client';
import React, { useMemo, useRef, useState } from 'react';

type Usuario = {
  id: string;
  codigo?: string | null;
  nombre?: string | null;
  apellido?: string | null;
  documento?: string | null;
  correo?: string | null; // la API /api/usuarios lo normaliza (puede venir como "email")
};

type CrearOrdenPayload = {
  usuarioId: string;
  servicio: 'internet' | 'television';
  tipo:
    | 'corte'
    | 'baja_total'
    | 'traslado'
    | 'mantenimiento'
    | 'cambio_equipo'
    | 'reconexion'
    | 'recontratacion';
  observaciones?: string | null;
};

const API = '/api';

export default function CrearOrdenDeServicio() {
  // --------- Estado UI ---------
  const [query, setQuery] = useState(''); // código/doc/nombre
  const [buscando, setBuscando] = useState(false);
  const [sugCargando, setSugCargando] = useState(false);
  const [sugerencias, setSugerencias] = useState<Usuario[]>([]);
  const [mostrarSug, setMostrarSug] = useState(false);

  const [cliente, setCliente] = useState<Usuario | null>(null);

  const [servicio, setServicio] = useState<'internet' | 'television'>('internet');
  const [tipo, setTipo] = useState<CrearOrdenPayload['tipo']>('mantenimiento');
  const [observaciones, setObservaciones] = useState('');

  const [enviando, setEnviando] = useState(false);
  const [flash, setFlash] = useState<{ ok: boolean; msg: string } | null>(null);
  const [creadaEn, setCreadaEn] = useState<Date | null>(null);
  const [ordenCreada, setOrdenCreada] = useState<{ id: string; codigo: string } | null>(null);

  const inputRef = useRef<HTMLInputElement | null>(null);

  // --------- Helpers ---------
  const clienteNombre = useMemo(() => {
    if (!cliente) return '';
    const nom = [cliente.nombre, cliente.apellido].filter(Boolean).join(' ').trim();
    return nom || '(sin nombre)';
  }, [cliente]);

  function hideSugerenciasSoon() {
    setTimeout(() => setMostrarSug(false), 120);
  }

  // --------- Buscar exacto por código o documento ---------
  async function buscarExacto() {
    setFlash(null);
    setCliente(null);
    setSugerencias([]);
    setMostrarSug(false);

    const q = query.trim();
    if (!q) {
      setFlash({ ok: false, msg: 'Ingresa código, documento o nombre.' });
      return;
    }

    setBuscando(true);
    try {
      const url = new URL(`${API}/usuarios`, location.origin);
      url.searchParams.set('codigo_o_documento', q);
      const r = await fetch(url.toString(), { cache: 'no-store' });
      if (!r.ok) {
        setFlash({ ok: false, msg: `No se pudo buscar el cliente (HTTP ${r.status}).` });
        return;
      }
      const data = await r.json();
      if (!data || !data.id) {
        // sin match exacto → sugerencias por nombre
        await buscarSugerencias(q);
        return;
      }
      setCliente(data as Usuario);
    } catch (e: any) {
      setFlash({ ok: false, msg: e?.message || 'Error buscando cliente.' });
    } finally {
      setBuscando(false);
    }
  }

  // --------- Búsqueda por nombre (autocompletar) ---------
  async function buscarSugerencias(q: string) {
    const term = q.trim();
    if (term.length < 2) {
      setSugerencias([]);
      return;
    }
    setSugCargando(true);
    try {
      const url = new URL(`${API}/usuarios`, location.origin);
      url.searchParams.set('search', term); // implementado en /api/usuarios
      const r = await fetch(url.toString(), { cache: 'no-store' });
      if (!r.ok) {
        setSugerencias([]);
        return;
      }
      const arr = (await r.json()) as Usuario[];
      setSugerencias(Array.isArray(arr) ? arr.slice(0, 12) : []);
      setMostrarSug(true);
    } catch {
      setSugerencias([]);
    } finally {
      setSugCargando(false);
    }
  }

  async function onChangeQuery(v: string) {
    setQuery(v);
    setCliente(null);
    setFlash(null);
    if (v.trim().length >= 2) await buscarSugerencias(v);
    else {
      setSugerencias([]);
      setMostrarSug(false);
    }
  }

  function seleccionarCliente(u: Usuario) {
    setCliente(u);
    setQuery(u.codigo || u.documento || [u.nombre, u.apellido].filter(Boolean).join(' ') || '');
    setMostrarSug(false);
    setSugerencias([]);
    inputRef.current?.blur();
  }

  // --------- Crear orden ---------
  async function crearOrden(e: React.FormEvent) {
    e.preventDefault();
    setFlash(null);
    setOrdenCreada(null);
    setCreadaEn(null);

    if (!cliente?.id) {
      setFlash({ ok: false, msg: 'Primero selecciona un cliente válido.' });
      return;
    }
    const payload: CrearOrdenPayload = {
      usuarioId: cliente.id,
      servicio,
      tipo,
      observaciones: observaciones.trim() || undefined,
    };

    try {
      setEnviando(true);
      const r = await fetch(`${API}/ordenes`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const txt = await r.text();
      if (!r.ok) {
        setFlash({ ok: false, msg: `No se pudo crear la orden (HTTP ${r.status}): ${txt.slice(0, 300)}` });
        return;
      }
      const j = JSON.parse(txt);
      setOrdenCreada({ id: j.id, codigo: j.codigo });
      setCreadaEn(new Date());
      setFlash({ ok: true, msg: 'Orden creada con éxito.' });

      // Reset suave (mantenemos el cliente)
      setServicio('internet');
      setTipo('mantenimiento');
      setObservaciones('');
    } catch (e: any) {
      setFlash({ ok: false, msg: e?.message || 'Error creando la orden.' });
    } finally {
      setEnviando(false);
    }
  }

  // --------- UI ---------
  return (
    <div className="min-h-screen bg-gray-50 p-6">
      <div className="mx-auto max-w-5xl">
        <div className="flex items-center justify-between">
          <h1 className="text-3xl font-extrabold text-slate-900">Crear orden de servicio</h1>
          <div className="flex items-center gap-3">
            <a href="/agenda" className="text-blue-600 hover:text-blue-700 hover:underline">Ir a Agenda →</a>
            <a href="/tecnico" className="text-blue-600 hover:text-blue-700 hover:underline">Ir a Técnico →</a>
          </div>
        </div>
        <p className="text-sm text-slate-600 mt-1">
          Genera órdenes como <em>corte</em>, <em>mantenimiento</em>, <em>reconexión</em>, etc.
        </p>

        {flash && (
          <div className={`mt-4 rounded-xl p-3 border shadow-sm ${
            flash.ok
              ? 'bg-emerald-50 text-emerald-800 border-emerald-200'
              : 'bg-rose-50 text-rose-800 border-rose-200'
          }`}>
            <div className="flex items-center justify-between gap-3">
              <div>{flash.msg}</div>
              {flash.ok && ordenCreada && (
                <a
                  href={`/tecnico/${ordenCreada.codigo}`}
                  className="px-3 py-1 rounded-lg bg-white border border-current hover:bg-gray-50"
                >
                  Abrir orden
                </a>
              )}
            </div>
          </div>
        )}

        {/* Card: Cliente */}
        <div className="bg-white rounded-2xl p-4 border border-slate-200 shadow-sm mt-6">
          <div className="font-bold text-slate-700 mb-2">Cliente</div>

          <div className="relative">
            <div className="grid grid-cols-[1fr_auto] gap-3">
              <input
                ref={inputRef}
                value={query}
                onChange={(e) => onChangeQuery(e.target.value)}
                onFocus={() => { if (sugerencias.length) setMostrarSug(true); }}
                onBlur={hideSugerenciasSoon}
                placeholder="Código, documento o nombre (ej.: USR-0001 / CC-123 / Ana Gómez)…"
                className="bg-white rounded-xl px-3 py-2 text-sm border border-slate-200 shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <button
                onClick={buscarExacto}
                disabled={buscando}
                type="button"
                className="px-4 py-2 rounded-xl bg-blue-600 text-white shadow hover:bg-blue-700 disabled:opacity-60"
              >
                {buscando ? 'Buscando…' : 'Buscar'}
              </button>
            </div>

            {/* Panel de sugerencias */}
            {mostrarSug && (
              <div className="absolute z-10 mt-2 w-full bg-white border border-slate-200 rounded-xl shadow-lg overflow-hidden">
                {sugCargando && <div className="px-3 py-2 text-sm text-slate-500">Buscando…</div>}
                {!sugCargando && sugerencias.length === 0 && (
                  <div className="px-3 py-2 text-sm text-slate-500">No hay coincidencias.</div>
                )}
                {!sugCargando && sugerencias.map((u) => {
                  const linea1 = [u.nombre, u.apellido].filter(Boolean).join(' ') || u.codigo || '—';
                  const linea2 = [u.codigo, u.documento, u.correo].filter(Boolean).join(' · ');
                  return (
                    <button
                      key={u.id}
                      type="button"
                      className="w-full text-left px-3 py-2 hover:bg-slate-50"
                      onMouseDown={(e) => e.preventDefault()}
                      onClick={() => seleccionarCliente(u)}
                    >
                      <div className="text-sm text-slate-900">{linea1}</div>
                      <div className="text-xs text-slate-500">{linea2}</div>
                    </button>
                  );
                })}
              </div>
            )}
          </div>

          <div className="grid md:grid-cols-2 gap-3 mt-3">
            <div>
              <div className="text-xs text-slate-500">Nombre</div>
              <div className="mt-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm">
                {cliente ? clienteNombre : '—'}
              </div>
            </div>
            <div>
              <div className="text-xs text-slate-500">Correo electrónico</div>
              <div className="mt-1 bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm">
                {cliente?.correo || '—'}
              </div>
            </div>
          </div>
        </div>

        {/* Card: Datos de la orden */}
        <form onSubmit={crearOrden}>
          <div className="bg-white rounded-2xl p-4 border border-slate-200 shadow-sm mt-6">
            <div className="font-bold text-slate-700 mb-2">Detalle de la orden</div>

            <div className="grid md:grid-cols-3 gap-3">
              <div>
                <div className="text-xs text-slate-500">Servicio</div>
                <select
                  value={servicio}
                  onChange={(e) => setServicio(e.target.value as any)}
                  className="mt-1 bg-white rounded-lg px-3 py-2 text-sm border border-slate-200 w-full focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  <option value="internet">Internet</option>
                  <option value="television">Televisión</option>
                </select>
              </div>

              <div className="md:col-span-2">
                <div className="text-xs text-slate-500">Tipo de orden</div>
                <div className="mt-1 grid sm:grid-cols-3 gap-2">
                  {([
                    ['mantenimiento', 'Mantenimiento'],
                    ['corte', 'Corte'],
                    ['reconexion', 'Reconexión'],
                    ['baja_total', 'Baja total'],
                    ['traslado', 'Traslado'],
                    ['cambio_equipo', 'Cambio de equipo'],
                    ['recontratacion', 'Recontratación'],
                  ] as const).map(([value, label]) => (
                    <label
                      key={value}
                      className={`flex items-center gap-2 px-3 py-2 rounded-lg border cursor-pointer ${
                        tipo === value
                          ? 'border-blue-500 bg-blue-50'
                          : 'border-slate-200 bg-white hover:bg-slate-50'
                      }`}
                    >
                      <input
                        type="radio"
                        name="tipo"
                        value={value}
                        checked={tipo === value}
                        onChange={() => setTipo(value)}
                      />
                      <span className="text-sm text-slate-900">{label}</span>
                    </label>
                  ))}
                </div>
              </div>
            </div>

            <div className="mt-3">
              <div className="text-xs text-slate-500">Observaciones</div>
              <textarea
                value={observaciones}
                onChange={(e) => setObservaciones(e.target.value)}
                rows={4}
                placeholder="Notas internas o información para el técnico…"
                className="mt-1 w-full bg-white rounded-lg px-3 py-2 text-sm border border-slate-200 focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
          </div>

          <div className="bg-white rounded-2xl p-4 border border-slate-200 shadow-sm mt-6 flex items-center justify-between">
            <div className="text-sm text-slate-600">
              Al crear, se fijará la fecha y hora de generación y la orden quedará en estado <b>CREADA</b>.
            </div>
            <button
              type="submit"
              disabled={!cliente?.id || enviando}
              className="px-5 py-2 rounded-xl shadow text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-60"
            >
              {enviando ? 'Creando…' : 'Crear orden'}
            </button>
          </div>
        </form>

        {creadaEn && (
          <div className="mt-4 text-sm text-slate-600">
            Fecha y hora de creación: <b>{creadaEn.toLocaleString()}</b>
          </div>
        )}
      </div>
    </div>
  );
}
