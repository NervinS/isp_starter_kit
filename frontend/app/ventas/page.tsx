'use client';
import { useEffect, useMemo, useRef, useState } from 'react';

type Plan = { codigo: string; nombre: string; vel_mbps: number; alta_costo: number | string; mensual: number | string };
type Municipio = { codigo: string; nombre: string };
type Via = { codigo: string; nombre: string };

const API = '/api';
const TV_MENSUAL = 30000;

const num = (v: any) => (typeof v === 'string' ? Number(v) : v) || 0;
const upNoSpaces = (s: string) => (s || '').toUpperCase().replace(/\s+/g, '');

// ⚠️ Micro-cambio 1: usar FileReader en el navegador
async function fileToBase64(f: File): Promise<string> {
  return await new Promise((resolve, reject) => {
    const fr = new FileReader();
    fr.onload = () => resolve(String(fr.result));
    fr.onerror = reject;
    fr.readAsDataURL(f); // data:<mime>;base64,XXXX
  });
}

export default function VentasPage() {
  // ------- cliente
  const [nombre, setNombre] = useState('');
  const [apellido, setApellido] = useState('');
  const [documento, setDocumento] = useState('');
  const [telefono, setTelefono] = useState('');
  const [correo, setCorreo] = useState('');
  const [observaciones, setObs] = useState('');

  // ------- planes
  const [planes, setPlanes] = useState<Plan[]>([]);
  const [planSel, setPlanSel] = useState('');
  const planObj = useMemo(() => planes.find(p => p.codigo === planSel) || null, [planes, planSel]);
  const alta = planObj ? num(planObj.alta_costo) : 0;
  const mensualInt = planObj ? num(planObj.mensual) : 0;
  const [incluyeTv, setIncluyeTv] = useState(false);
  const mensualTotal = mensualInt + (incluyeTv ? TV_MENSUAL : 0);

  // ------- catálogos dirección
  const [municipios, setMunicipios] = useState<Municipio[]>([]);
  const [vias, setVias] = useState<Via[]>([]);
  const [municipioSel, setMunicipioSel] = useState('BARRANQUILLA');
  const [zonaSel, setZonaSel] = useState<'BARRIO' | 'CONJUNTO' | 'COMUNA'>('BARRIO');

  const [sectores, setSectores] = useState<string[]>([]);
  const [sectoresLoading, setSectoresLoading] = useState(false);
  const [sectorSel, setSectorSel] = useState('');
  const [sectorManual, setSectorManual] = useState('');

  const [viaSel, setViaSel] = useState('');
  const [viaNombre, setViaNombre] = useState('');
  const [viaIndicador, setViaIndicador] = useState('');
  const [orientacion, setOrientacion] = useState<'NORTE'|'SUR'|'ESTE'|'OESTE'|'NULL'>('NULL');
  const [numeroCasa, setNumeroCasa] = useState('');

  // ------- adjuntos/firma (UI inputs y copias “persistentes” para pagar)
  const [reciboFile, setReciboFile] = useState<File | null>(null);
  const [cedulaFile, setCedulaFile] = useState<File | null>(null);
  const [firmaDataUrl, setFirmaDataUrl] = useState<string | null>(null);     // preview/canvas
  const [firmaPersist, setFirmaPersist] = useState<string | null>(null);      // se usa al pagar
  const [reciboB64, setReciboB64] = useState<string | null>(null);
  const [cedulaB64, setCedulaB64] = useState<string | null>(null);

  // ------- pagos y mensajes
  const [codigoPagar, setCodigoPagar] = useState('');
  const [reciboUrl, setReciboUrl] = useState<string | null>(null);
  const [contratoUrl, setContratoUrl] = useState<string | null>(null);
  const [ventasCreadas, setVentasCreadas] = useState<{codigo:string; total:number}[]>([]);

  const [msg, setMsg] = useState('');
  const [loadingCrear, setLoadingCrear] = useState(false);
  const [loadingPagar, setLoadingPagar] = useState(false);

  // ------- firma (canvas)
  const canvasRef = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const cv = canvasRef.current;
    if (!cv) return;
    const ctx = cv.getContext('2d');
    if (!ctx) return;
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    let drawing = false;
    const down = (e: PointerEvent) => {
      drawing = true;
      ctx.beginPath();
      const r = cv.getBoundingClientRect();
      ctx.moveTo(e.clientX - r.left, e.clientY - r.top);
      cv.setPointerCapture(e.pointerId);
    };
    const move = (e: PointerEvent) => {
      if (!drawing) return;
      const r = cv.getBoundingClientRect();
      ctx.lineTo(e.clientX - r.left, e.clientY - r.top);
      ctx.stroke();
    };
    const up = (e: PointerEvent) => {
      drawing = false;
      cv.releasePointerCapture(e.pointerId);
      const data = cv.toDataURL('image/png');
      setFirmaDataUrl(data);
      setFirmaPersist(data); // guardamos copia para usarla tras limpiar UI
    };
    cv.addEventListener('pointerdown', down);
    cv.addEventListener('pointermove', move);
    cv.addEventListener('pointerup', up);
    return () => {
      cv.removeEventListener('pointerdown', down);
      cv.removeEventListener('pointermove', move);
      cv.removeEventListener('pointerup', up);
    };
  }, []);

  // ------- carga inicial
  useEffect(() => {
    (async () => {
      try {
        const [rp, rm, rv] = await Promise.all([
          fetch(`${API}/planes`, { cache: 'no-store' }),
          fetch(`${API}/catalogos/municipios`, { cache: 'no-store' }),
          fetch(`${API}/catalogos/vias`, { cache: 'no-store' }),
        ]);
        const jp = rp.ok ? await rp.json() : [];
        const jm = rm.ok ? await rm.json() : [];
        const jv = rv.ok ? await rv.json() : [];
        setPlanes(Array.isArray(jp) ? jp : []);
        setMunicipios(Array.isArray(jm) ? jm : []);
        setVias(Array.isArray(jv) ? jv : []);
        if (Array.isArray(jp) && jp.length) setPlanSel(jp[0].codigo);
        if (Array.isArray(jv) && jv.length) setViaSel(jv[0].codigo);
      } catch {}
    })();
  }, []);

  // ------- cargar sectores cuando cambian municipio/zona
  useEffect(() => {
    (async () => {
      setSectores([]);
      setSectorSel('');
      setSectorManual('');
      if (!municipioSel || !zonaSel) return;
      setSectoresLoading(true);
      try {
        const url = `${API}/catalogos/sectores?municipio=${encodeURIComponent(municipioSel)}&zona=${encodeURIComponent(zonaSel)}`;
        const r = await fetch(url, { cache: 'no-store' });
        const j = r.ok ? await r.json() : [];
        const arr: string[] = Array.isArray(j) ? j : [];
        setSectores(arr);
        if (arr.length === 1) setSectorSel(arr[0]);
      } catch {
        setSectores([]);
      } finally {
        setSectoresLoading(false);
      }
    })();
  }, [municipioSel, zonaSel]);

  // ------- preview dirección
  const dirPreview = useMemo(() => {
    const zonaTxt = zonaSel;
    const sec = (sectorSel || sectorManual || '').toUpperCase();
    const viaTxt = viaSel || 'VIA';
    const nVia = upNoSpaces(viaNombre);
    const ind = upNoSpaces(viaIndicador);
    const ori = orientacion === 'NULL' ? '' : ` ${orientacion}`;
    const nCasa = (numeroCasa || '').replace(/\s+/g, '');
    const comp = ind ? ` # ${ind}` : '';
    return `MUNICIPIO ${municipioSel}, ${zonaTxt} ${sec}, ${viaTxt} ${nVia}${comp}${ori} - ${nCasa}`.replace(/\s+/g, ' ').trim();
  }, [municipioSel, zonaSel, sectorSel, sectorManual, viaSel, viaNombre, viaIndicador, orientacion, numeroCasa]);

  // ------- validación mínima
  const requireFront = (): string | null => {
    if (!nombre.trim()) return 'Nombre es obligatorio';
    if (!apellido.trim()) return 'Apellido es obligatorio';
    if (!documento.trim()) return 'Documento es obligatorio';
    if (!planSel) return 'Selecciona un plan';
    if (!reciboFile) return 'Adjunta foto del recibo público';
    if (!cedulaFile) return 'Adjunta foto de la cédula';
    if (!firmaPersist) return 'Captura la firma del cliente';
    if (!municipioSel) return 'Selecciona municipio';
    if (!(sectorSel || sectorManual)) return `Selecciona o escribe el ${zonaSel.toLowerCase()}`;
    if (!viaSel || !viaNombre.trim() || !numeroCasa.trim()) return 'Completa vía, número de vía y número de casa';
    return null;
  };

  // ------- helpers de limpieza UI (sin perder lo necesario)
  const clearCanvas = () => {
    const cv = canvasRef.current; if (!cv) return;
    const ctx = cv.getContext('2d'); if (!ctx) return;
    ctx.clearRect(0, 0, cv.width, cv.height);
    setFirmaDataUrl(null);
    // mantenemos firmaPersist para usarla en el pagar
  };

  const clearFilesInputs = () => {
    setReciboFile(null);
    setCedulaFile(null);
  };

  function resetFormularioTrasCrear() {
    // datos de cliente
    setNombre(''); setApellido(''); setDocumento(''); setTelefono(''); setCorreo(''); setObs('');
    // plan
    setIncluyeTv(false);
    if (planes.length) setPlanSel(planes[0].codigo);
    // dirección (dejamos municipio y zona en defaults)
    setSectorSel(''); setSectorManual('');
    setViaNombre(''); setViaIndicador(''); setOrientacion('NULL'); setNumeroCasa('');
    if (vias.length) setViaSel(vias[0].codigo);
    // limpiar UI de adjuntos/firma, pero conservar copias persistentes
    clearCanvas();
    clearFilesInputs();
  }

  // ⚠️ Micro-cambio 2: NO limpiar reciboUrl/contratoUrl para que queden los botones
  function resetTrasPagar() {
    setCodigoPagar('');        // evita dobles pagos
    // no tocar las URLs
    setFirmaPersist(null);
    setReciboB64(null);
    setCedulaB64(null);
  }

  // ------- acciones
  async function crearVenta() {
    try {
      setMsg('');
      const err = requireFront();
      if (err) { setMsg(err); return; }

      setLoadingCrear(true);

      // generar copias base64 de adjuntos (y guardarlas para pagar)
      if (reciboFile && !reciboB64) setReciboB64(await fileToBase64(reciboFile));
      if (cedulaFile && !cedulaB64) setCedulaB64(await fileToBase64(cedulaFile));

      const body = {
        cliente_nombre: nombre,
        cliente_apellido: apellido,
        documento,
        telefono,
        correo,
        observaciones,

        plan_codigo: planSel,
        incluye_tv: incluyeTv,

        direccion: {
          municipio: municipioSel,
          zona: zonaSel,
          sector: (sectorSel || sectorManual || '').toUpperCase(),
          via: viaSel,
          via_nombre: upNoSpaces(viaNombre),
          via_indicador: upNoSpaces(viaIndicador),
          orientacion,
          numero_casa: (numeroCasa || '').replace(/\s+/g, ''),
          preview: dirPreview,
        },

        adjuntos: {
          tiene_recibo: !!reciboFile,
          tiene_cedula: !!cedulaFile,
          tiene_firma: !!firmaPersist,
        },
      };

      const res = await fetch(`${API}/ventas`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

      const t = await res.text();
      if (!res.ok) throw new Error(`HTTP ${res.status}: ${t}`);
      const j = JSON.parse(t);
      setMsg(`Venta creada: ${j?.venta?.codigo || ''}`);
      if (j?.venta?.codigo) setCodigoPagar(j.venta.codigo);

      // limpiar UI para evitar doble creación
      resetFormularioTrasCrear();
    } catch (e: any) {
      setMsg(e?.message || String(e));
    } finally {
      setLoadingCrear(false);
    }
  }

  async function pagarVenta() {
    try {
      setMsg('');
      if (!codigoPagar.trim()) { setMsg('Ingresa el código de venta'); return; }

      setLoadingPagar(true);

      const res = await fetch(`${API}/ventas/pagar`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          codigo: codigoPagar.trim(),
          firma_base64: firmaPersist || null,
          recibo_base64: reciboB64 || null,
          cedula_base64: cedulaB64 || null,
        }),
      });
      const t = await res.text();
      if (!res.ok) throw new Error(`HTTP ${res.status}: ${t}`);
      const j = JSON.parse(t);
      setMsg(`Venta ${j?.venta?.codigo || codigoPagar} pagada`);
      setReciboUrl(j?.venta?.recibo_url || null);
      setContratoUrl(j?.venta?.contrato_url || null);

      // evitar dobles pagos (pero mantenemos las URLs para ver los botones)
      resetTrasPagar();
    } catch (e: any) {
      setMsg(e?.message || String(e));
    } finally {
      setLoadingPagar(false);
    }
  }

  async function cargarVentasCreadas() {
    try {
      setMsg('');
      const r = await fetch(`${API}/ventas?estado=creada`, { cache: 'no-store' });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const j = await r.json();
      const arr = Array.isArray(j) ? j : [];
      setVentasCreadas(arr.map((v: any) => ({ codigo: v.codigo, total: num(v.total) })));
    } catch (e: any) {
      setMsg(`No se pudo cargar la lista: ${e?.message || e}`);
    }
  }

  // ------- estilos (UI SaaS/CRM)
  return (
    <div style={styles.page}>
      <div style={styles.card}>
        <h1 style={styles.title}>Nueva Venta</h1>

        {/* Cliente */}
        <section style={styles.section}>
          <h3 style={styles.sectionTitle}>Cliente</h3>
          <div style={styles.grid2}>
            <input style={styles.input} placeholder="Nombre" value={nombre} onChange={e=>setNombre(e.target.value)} />
            <input style={styles.input} placeholder="Apellido" value={apellido} onChange={e=>setApellido(e.target.value)} />
          </div>
          <div style={styles.grid3}>
            <input style={styles.input} placeholder="Documento" value={documento} onChange={e=>setDocumento(e.target.value)} />
            <input style={styles.input} placeholder="Teléfono" value={telefono} onChange={e=>setTelefono(e.target.value)} />
            <input style={styles.input} placeholder="Correo" value={correo} onChange={e=>setCorreo(e.target.value)} />
          </div>
          <textarea style={{...styles.input, minHeight: 70}} placeholder="Observaciones" value={observaciones} onChange={e=>setObs(e.target.value)} />
        </section>

        {/* Plan */}
        <section style={styles.section}>
          <h3 style={styles.sectionTitle}>Plan</h3>
          <div style={styles.grid2}>
            <select style={styles.input} value={planSel} onChange={e=>setPlanSel(e.target.value)}>
              {planes.map(p=>(
                <option key={p.codigo} value={p.codigo}>
                  {p.nombre} — {num(p.vel_mbps)}M — ${num(p.mensual).toLocaleString('es-CO')}
                </option>
              ))}
            </select>
            <label style={{...styles.checkbox, ...styles.input}}>
              <input type="checkbox" checked={incluyeTv} onChange={e=>setIncluyeTv(e.target.checked)} />
              <span>Incluir TV (+ $30.000/mes)</span>
            </label>
          </div>
          <div style={styles.hint}>
            <div><b>Instalación hoy:</b> ${alta.toLocaleString('es-CO')}</div>
            <div><b>Mensualidad:</b> ${mensualInt.toLocaleString('es-CO')}
              {incluyeTv ? ` + $${TV_MENSUAL.toLocaleString('es-CO')} (TV)` : ''} = <b>${mensualTotal.toLocaleString('es-CO')}</b>
            </div>
          </div>
        </section>

        {/* Dirección */}
        <section style={styles.section}>
          <h3 style={styles.sectionTitle}>Dirección</h3>
          <div style={styles.grid2}>
            <select style={styles.input} value={municipioSel} onChange={e=>setMunicipioSel(e.target.value.toUpperCase())}>
              {municipios.map(m=> <option key={m.codigo} value={m.codigo}>{m.nombre}</option>)}
            </select>
            <select style={styles.input} value={zonaSel} onChange={e=>setZonaSel(e.target.value as any)}>
              <option value="BARRIO">BARRIO</option>
              <option value="CONJUNTO">CONJUNTO</option>
              <option value="COMUNA">COMUNA</option>
            </select>
          </div>

          <div>
            <select
              style={styles.input}
              value={sectorSel}
              onChange={e=>setSectorSel(e.target.value)}
              disabled={sectoresLoading || (!sectoresLoading && sectores.length === 0)}
            >
              <option value="">{sectoresLoading ? 'Cargando…' : `${zonaSel}…`}</option>
              {sectores.map(s => <option key={s} value={s}>{s}</option>)}
            </select>
            {!sectoresLoading && sectores.length === 0 && (
              <input style={{...styles.input, marginTop:8}} placeholder={`${zonaSel} (escribir si no aparece)…`} value={sectorManual} onChange={e=>setSectorManual(upNoSpaces(e.target.value))} />
            )}
          </div>

          <div style={styles.grid2}>
            <select style={styles.input} value={viaSel} onChange={e=>setViaSel(e.target.value)}>
              {vias.map(v=> <option key={v.codigo} value={v.codigo}>{v.nombre}</option>)}
            </select>
            <select style={styles.input} value={orientacion} onChange={e=>setOrientacion(e.target.value as any)}>
              <option value="NULL">NULL</option>
              <option value="NORTE">NORTE</option>
              <option value="SUR">SUR</option>
              <option value="ESTE">ESTE</option>
              <option value="OESTE">OESTE</option>
            </select>
          </div>

          <div style={styles.grid3}>
            <input style={styles.input} placeholder="N°/Nombre de vía (sin espacios)" value={viaNombre} onChange={e=>setViaNombre(e.target.value)} />
            <input style={styles.input} placeholder="N° complementario (ej. 5BIS)" value={viaIndicador} onChange={e=>setViaIndicador(e.target.value)} />
            <input style={styles.input} placeholder="Número de casa" value={numeroCasa} onChange={e=>setNumeroCasa(e.target.value)} />
          </div>

          <div style={styles.preview}><b>Vista previa:</b> {dirPreview}</div>
        </section>

        {/* Adjuntos y firma */}
        <section style={styles.section}>
          <h3 style={styles.sectionTitle}>Adjuntos y firma</h3>
          <div style={styles.grid2}>
            <label style={styles.inputLabel}>Foto recibo público
              <input style={styles.inputFile} type="file" accept="image/*" onChange={async e=>{
                const f = e.target.files?.[0] || null;
                setReciboFile(f);
                setReciboB64(f ? await fileToBase64(f) : null);
              }} />
            </label>
            <label style={styles.inputLabel}>Foto cédula
              <input style={styles.inputFile} type="file" accept="image/*" onChange={async e=>{
                const f = e.target.files?.[0] || null;
                setCedulaFile(f);
                setCedulaB64(f ? await fileToBase64(f) : null);
              }} />
            </label>
          </div>

          <div>
            <div style={{marginBottom:6}}>Firma del cliente</div>
            <canvas ref={canvasRef} width={640} height={160} style={styles.canvas} />
            <div style={{marginTop:8, display:'flex', gap:8}}>
              <button style={styles.btnGhost} onClick={clearCanvas}>Borrar firma</button>
            </div>
          </div>
        </section>

        {/* Acciones */}
        <div style={{display:'flex', gap:12, flexWrap:'wrap'}}>
          <button style={styles.btnPrimary} onClick={crearVenta} disabled={loadingCrear}>
            {loadingCrear ? 'Creando…' : 'Crear venta'}
          </button>
        </div>

        {msg && <div style={styles.alert}>{msg}</div>}

        <hr style={{border:'none', height:1, background:'#eee', margin:'20px 0'}} />

        {/* Pago */}
        <h3 style={styles.sectionTitle}>Pagar venta</h3>
        <div style={{display:'flex', gap:8}}>
          <input style={{...styles.input, flex:1}} placeholder="Código de venta (VEN-000123)" value={codigoPagar} onChange={e=>setCodigoPagar(e.target.value)} />
          <button style={styles.btnPrimary} onClick={pagarVenta} disabled={loadingPagar}>
            {loadingPagar ? 'Pagando…' : 'Pagar'}
          </button>
        </div>

        {(reciboUrl || contratoUrl) && (
          <div style={{marginTop:12, display:'flex', gap:12, flexWrap:'wrap'}}>
            {reciboUrl && <a style={styles.btnLink} href={reciboUrl} target="_blank" rel="noreferrer">Descargar Recibo (PDF)</a>}
            {contratoUrl && <a style={styles.btnLink} href={contratoUrl} target="_blank" rel="noreferrer">Descargar Contrato (PDF)</a>}
          </div>
        )}

        <div style={{ marginTop:14, display:'flex', gap:8, flexWrap:'wrap' }}>
          <button style={styles.btnGhost} onClick={cargarVentasCreadas}>Ver ventas creadas</button>
          <a style={styles.btnGhost} href="/ordenes">Ver órdenes pendientes</a>
        </div>

        {ventasCreadas.length > 0 && (
          <ul style={{ marginTop:8 }}>
            {ventasCreadas.map(v=>(
              <li key={v.codigo} style={{marginBottom:6}}>
                {v.codigo} — ${v.total.toLocaleString('es-CO')}
                <button style={{...styles.btnGhost, marginLeft:8}} onClick={()=>setCodigoPagar(v.codigo)}>Usar para pagar</button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

/* ---------- estilos inline (sin Tailwind) ---------- */
const styles: Record<string, any> = {
  page: { background:'#f4f6f8', minHeight:'100vh', padding:'32px 16px', fontFamily:'Inter, system-ui, -apple-system, Segoe UI, Roboto, sans-serif', color:'#0f172a' },
  card: { maxWidth: 980, margin:'0 auto', background:'#fff', borderRadius:16, boxShadow:'0 10px 30px rgba(2,12,27,.08)', padding:24 },
  title: { margin:'0 0 8px 0', fontSize:28, fontWeight:800, letterSpacing:.2 },
  section: { marginTop:16 },
  sectionTitle: { fontSize:16, fontWeight:700, margin:'0 0 10px 0', color:'#1f2937' },
  grid2: { display:'grid', gridTemplateColumns:'1fr 1fr', gap:10 },
  grid3: { display:'grid', gridTemplateColumns:'1fr 1fr 1fr', gap:10 },
  input: { width:'100%', padding:'10px 12px', border:'1px solid #e5e7eb', borderRadius:10, outline:'none', background:'#fff',
           boxShadow:'inset 0 1px 0 rgba(0,0,0,.02)', transition:'border .2s' },
  inputLabel: { display:'flex', flexDirection:'column', gap:6, border:'1px dashed #cbd5e1', borderRadius:12, padding:12, background:'#fafafa' },
  inputFile: { display:'block' },
  checkbox: { display:'flex', alignItems:'center', gap:8 },
  hint: { marginTop:8, fontSize:14, color:'#4b5563' },
  preview: { marginTop:8, fontSize:14, color:'#0f172a', background:'#f8fafc', border:'1px solid #e5e7eb', borderRadius:10, padding:'8px 10px' },
  canvas: { width:'100%', maxWidth:640, border:'1px solid #e5e7eb', borderRadius:12, background:'#fff', boxShadow:'inset 0 1px 0 rgba(0,0,0,.02)' },
  btnPrimary: { background:'#2563eb', color:'#fff', border:'none', padding:'10px 14px', borderRadius:12, cursor:'pointer',
                boxShadow:'0 6px 14px rgba(37,99,235,.18)', fontWeight:600 },
  btnGhost: { background:'#eef2ff', color:'#1e3a8a', border:'1px solid #c7d2fe', padding:'8px 12px', borderRadius:12, cursor:'pointer', fontWeight:600 },
  btnLink: { background:'#10b981', color:'#fff', padding:'8px 12px', borderRadius:12, textDecoration:'none', boxShadow:'0 6px 14px rgba(16,185,129,.18)', fontWeight:700 },
  alert: { marginTop:12, background:'#eff6ff', border:'1px solid #bfdbfe', color:'#1e40af', padding:'10px 12px', borderRadius:10 }
};
