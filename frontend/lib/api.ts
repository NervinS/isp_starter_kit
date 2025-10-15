// frontend/lib/api.ts
export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  // llamamos al proxy del front
  const url = `/api/bk/${path.replace(/^\/+/, "")}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...(init?.headers || {}),
    },
    cache: "no-store",
  });
  // si la respuesta no es JSON (p.ej. PDF info), intenta parsear igual
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`API ${res.status}: ${text || res.statusText}`);
  }
  try {
    return JSON.parse(text) as T;
  } catch {
    // por si el backend devuelve texto plano ocasionalmente
    return text as unknown as T;
  }
}

// Azúcar para POST JSON
export async function apiPost<T>(path: string, body: any, extra?: RequestInit): Promise<T> {
  return api<T>(path, {
    method: "POST",
    body: JSON.stringify(body),
    ...(extra || {}),
  });
}
