const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000/api/v1";

export type Resource = { id: string; title: string; summary: string; body: string; audience: string; resource_type: string; featured: boolean; category: { name: string; slug: string }; tags: { name: string; slug: string }[] };
export type User = { id: string; email: string; name: string; role: "user" | "admin" };

export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const token = localStorage.getItem("access_token");
  const response = await fetch(`${API_URL}${path}`, { ...init, headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}), ...init?.headers } });
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.detail ?? payload.error?.message ?? "요청을 처리하지 못했습니다.");
  }
  return response.json();
}
