'use client';
import { useEffect, useState } from 'react';

// Solo lo mostramos en pantalla para referencia; las llamadas reales van a /api/*
const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://127.0.0.1:3000/v1';

type Usuario = { id:string; codigo:string; nombre:string; apellido:string; documento:string; estado:string; };

export default function Home() {
  const [health, setHealth] = useState<any>(null);
  const [q, setQ] = useState('');
  const [usuarios, setUsuarios] = useState<Usuario[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    fetch(`/api/health`, { cache: 'no-store' })
      .then(r => r.json())
      .then(setHealth)
      .catch(e => setHealth({ ok:false, err: String(e) }));
  }, []);

  const buscar = async () => {
    setErr(null); setUsuarios(null); setLoading(true);
    try {
      const res = await fetch(`/api/usuarios?q=${encodeURIComponent(q)}`, { cache:'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setUsuarios(await res.json());
    } catch(e:any){ setErr(e.message||'Error'); } finally { setLoading(false); }
  };

  return (
    <main style={{ padding:24, fontFamily:'system-ui, Arial' }}>
      <h1>ISP FTTH - Frontend</h1>
      <div>API (referencia): <code>{API_BASE}</code></div>

      <section style={{ marginTop:16 }}>
        <h2>Health</h2>
        <pre style={{ background:'#f7f7f7', padding:12 }}>{JSON.stringify(health, null, 2)}</pre>
      </section>

      <section style={{ marginTop:16 }}>
        <h2>Buscar usuarios</h2>
        <div style={{ display:'flex', gap:8 }}>
          <input value={q} onChange={e=>setQ(e.target.value)} placeholder="Código / nombre / doc"
                 style={{ flex:1, padding:8, borderRadius:8, border:'1px solid #ccc' }}/>
          <button onClick={buscar} style={{ padding:'8px 12px', borderRadius:8 }}>Buscar</button>
        </div>
        {loading && <div>Cargando...</div>}
        {err && <div style={{ color:'crimson' }}>Error: {err}</div>}
        {usuarios && (
          <table style={{ width:'100%', borderCollapse:'collapse', marginTop:12 }}>
            <thead><tr>
              <th style={{ textAlign:'left', borderBottom:'1px solid #ddd', padding:6 }}>Código</th>
              <th style={{ textAlign:'left', borderBottom:'1px solid #ddd', padding:6 }}>Nombre</th>
              <th style={{ textAlign:'left', borderBottom:'1px solid #ddd', padding:6 }}>Documento</th>
              <th style={{ textAlign:'left', borderBottom:'1px solid #ddd', padding:6 }}>Estado</th>
            </tr></thead>
            <tbody>
              {usuarios.map(u=>(
                <tr key={u.id}>
                  <td style={{ borderBottom:'1px solid #f0f0f0', padding:6 }}>{u.codigo}</td>
                  <td style={{ borderBottom:'1px solid #f0f0f0', padding:6 }}>{u.nombre} {u.apellido}</td>
                  <td style={{ borderBottom:'1px solid #f0f0f0', padding:6 }}>{u.documento}</td>
                  <td style={{ borderBottom:'1px solid #f0f0f0', padding:6 }}>{u.estado}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </main>
  );
}
