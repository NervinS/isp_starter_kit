'use client';

import { useState } from 'react';

export default function PagarVenta() {
  const [codigo, setCodigo] = useState('');
  const [msg, setMsg] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function pagar() {
    setMsg(null);
    if (!codigo.trim()) {
      setMsg('Ingresa un código VEN-xxxxx');
      return;
    }
    setLoading(true);
    try {
      const res = await fetch('/api/ventas/pagar', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ codigo: codigo.trim() }),
        cache: 'no-store',
      });
      const text = await res.text();
      if (!res.ok) {
        setMsg(`Error ${res.status}: ${text.slice(0,200)}`);
      } else {
        setMsg(`OK: ${text}`);
      }
    } catch (e: any) {
      setMsg(e?.message || 'Error de red');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div style={{ marginTop: 16, padding: 12, border: '1px solid #ddd', borderRadius: 8 }}>
      <div style={{ display: 'flex', gap: 8 }}>
        <input
          value={codigo}
          onChange={(e) => setCodigo(e.target.value)}
          placeholder="VEN-000030"
          style={{ flex: 1, padding: 8, border: '1px solid #aaa', borderRadius: 6 }}
        />
        <button
          onClick={pagar}
          disabled={loading}
          style={{ padding: '8px 12px', border: '1px solid #000', borderRadius: 6 }}
        >
          {loading ? 'Pagando…' : 'Pagar'}
        </button>
      </div>
      {msg && <pre style={{ marginTop: 8, whiteSpace: 'pre-wrap' }}>{msg}</pre>}
      <div style={{ marginTop: 8, fontSize: 12, color: '#555' }}>
        Tip: después de pagar, ve a <a href="/ordenes" style={{ textDecoration: 'underline' }}>/ordenes</a> para ver la ORD pendiente.
      </div>
    </div>
  );
}

