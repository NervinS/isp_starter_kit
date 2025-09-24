// frontend/components/ordenes/BotonUbicacion.tsx
'use client';
import { useState } from 'react';

export default function BotonUbicacion({
  onCapture,
}: {
  onCapture: (coords: { lat: number; lng: number }) => void;
}) {
  const [estado, setEstado] = useState<'idle' | 'pidiendo' | 'ok' | 'error'>('idle');
  const [error, setError] = useState<string | null>(null);

  const capturar = () => {
    if (!('geolocation' in navigator)) {
      setError('Este dispositivo/navegador no soporta geolocalización');
      setEstado('error');
      return;
    }
    setEstado('pidiendo'); setError(null);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const lat = pos.coords.latitude;
        const lng = pos.coords.longitude;
        setEstado('ok');
        onCapture({ lat, lng });
      },
      (err) => {
        setEstado('error');
        setError(err.message || 'No fue posible obtener ubicación');
      },
      { enableHighAccuracy: true, timeout: 12000, maximumAge: 0 },
    );
  };

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={capturar}
        type="button"
        className="px-4 py-2 rounded-2xl shadow-sm bg-blue-600 hover:bg-blue-700 text-white transition"
      >
        Capturar ubicación
      </button>
      {estado === 'pidiendo' && <span className="text-gray-600">Solicitando ubicación…</span>}
      {estado === 'ok' && <span className="text-green-600">Ubicación capturada ✅</span>}
      {estado === 'error' && <span className="text-red-600">{error}</span>}
    </div>
  );
}
