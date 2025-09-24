// frontend/lib/api.ts
//
// Cliente ligero para el backend.
// - Usa NEXT_PUBLIC_API_BASE si existe (ej. "/api" con rewrites o URL absoluta).
// - Si no existe, cae por defecto a "http://127.0.0.1:3000/v1".
//
// Recomendado en prod: NEXT_PUBLIC_API_BASE="/api" + rewrite a tu API_BASE_SSR.

export const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE && process.env.NEXT_PUBLIC_API_BASE.trim() !== ''
    ? process.env.NEXT_PUBLIC_API_BASE
    : 'http://127.0.0.1:3000/v1';

type Metodo = 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';

type FetchOpts = {
  method?: Metodo;
  json?: any;          // body en JSON
  headers?: HeadersInit;
  cache?: RequestCache; // por defecto: 'no-store'
};

// ---- Función base ----
export async function api<T = any>(path: string, opts: FetchOpts = {}): Promise<T> {
  const url = `${API_BASE}${path}`;
  const res = await fetch(url, {
    method: opts.method || 'GET',
    headers: {
      'Content-Type': 'application/json',
      ...(opts.headers || {}),
    },
    body: opts.json !== undefined ? JSON.stringify(opts.json) : undefined,
    cache: opts.cache || 'no-store',
  });

  const text = await res.text().catch(() => '');
  let data: any = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    // Si no es JSON, lo dejamos como texto crudo en caso de error
    data = text;
  }

  if (!res.ok) {
    const msg =
      (data && typeof data === 'object' && (data.message || data.error)) ||
      (typeof data === 'string' && data) ||
      res.statusText ||
      `Error ${res.status}`;
    throw new Error(`${opts.method || 'GET'} ${path} -> ${res.status}: ${msg}`);
  }

  return (data as T);
}

// ---- Helpers compatibles con tu implementación previa ----
export async function apiGet<T>(path: string): Promise<T> {
  return api<T>(path, { method: 'GET' });
}

export async function apiPostJson<T>(path: string, body: any): Promise<T> {
  return api<T>(path, { method: 'POST', json: body });
}

// ---- APIs específicas (ordenes, tecnicos, materiales) ----
export const OrdenesAPI = {
  listar: <T = any>() => api<T>('/ordenes'),
  crear:  <T = any>(payload: any) => api<T>('/ordenes', { method: 'POST', json: payload }),
  cerrar: <T = any>(codigo: string, payload: any) => api<T>(`/ordenes/${codigo}/cerrar`, { method: 'POST', json: payload }),
  detalle:<T = any>(codigo: string) => api<T>(`/ordenes/${codigo}`),
};

export const TecnicosAPI = {
  listar: <T = any>() => api<T>('/tecnicos'),
  // crear/activar/desactivar si los necesitas:
  // crear:  <T = any>(nombre: string) => api<T>('/tecnicos', { method: 'POST', json: { nombre } }),
  // activo: <T = any>(id: string, activo: boolean) => api<T>(`/tecnicos/${id}/activo`, { method: 'PATCH', json: { activo } }),
};

export const MaterialesAPI = {
  listar: <T = any>() => api<T>('/materiales'),
  // crear:  <T = any>(m: { codigo: string; nombre: string; unidad?: string }) => api<T>('/materiales', { method: 'POST', json: m }),
};
