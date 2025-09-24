// frontend/components/ordenes/TarjetaCliente.tsx
'use client';

export default function TarjetaCliente({
  data,
}: {
  data?: { nombre?: string; codigo?: string; estadoServicio?: string; equipo?: string };
}) {
  const d = data || { nombre: '—', codigo: '—', estadoServicio: '—', equipo: '—' };
  return (
    <div className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
      <h3 className="text-sm font-semibold text-gray-800">Cliente</h3>
      <div className="mt-2 grid grid-cols-2 gap-2 text-sm">
        <div><span className="text-gray-500">Nombre:</span> <b>{d.nombre}</b></div>
        <div><span className="text-gray-500">Código:</span> <b>{d.codigo}</b></div>
        <div><span className="text-gray-500">Estado servicio:</span> <b>{d.estadoServicio}</b></div>
        <div><span className="text-gray-500">Equipo:</span> <b>{d.equipo}</b></div>
      </div>
    </div>
  );
}
