const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8000/api/v1";

export type Resource = { id: string; title: string; summary: string; body: string; audience: string; resource_type: string; featured: boolean; category: { name: string; slug: string }; tags: { name: string; slug: string }[] };
export type User = { id: string; email: string; name: string; role: "user" | "admin" };
export type Session = { access_token: string; refresh_token: string; user: User };

export function getSession(): Session | null {
  const raw = localStorage.getItem("session");
  if (raw) {
    try { return JSON.parse(raw) as Session; } catch { localStorage.removeItem("session"); }
  }
  const access = localStorage.getItem("access_token");
  const user = localStorage.getItem("user");
  return access && user ? { access_token: access, refresh_token: "", user: JSON.parse(user) as User } : null;
}
export function setSession(session: Session): void { localStorage.setItem("session", JSON.stringify(session)); }
export function clearSession(): void {
  localStorage.removeItem("session");
  localStorage.removeItem("access_token");
  localStorage.removeItem("user");
  window.dispatchEvent(new Event("auth:expired"));
}

async function request<T>(path: string, init: RequestInit = {}, canRefresh = true): Promise<T> {
  const session = getSession();
  const headers = new Headers(init.headers);
  if (!(init.body instanceof FormData)) headers.set("Content-Type", "application/json");
  if (session?.access_token) headers.set("Authorization", `Bearer ${session.access_token}`);
  const response = await fetch(`${API_URL}${path}`, { ...init, headers, credentials: "include" });
  if (response.status === 401 && canRefresh && session?.refresh_token && path !== "/auth/refresh") {
    const refreshed = await fetch(`${API_URL}/auth/refresh`, { method: "POST", credentials: "include", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ refresh_token: session.refresh_token }) });
    if (refreshed.ok) {
      setSession(await refreshed.json() as Session);
      return request<T>(path, init, false);
    }
    clearSession();
    throw new Error("세션이 만료되었습니다. 다시 로그인해 주세요.");
  }
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.detail ?? payload.error?.message ?? "요청을 처리하지 못했습니다.");
  }
  if (response.status === 204) return undefined as T;
  return response.json() as Promise<T>;
}
export function api<T>(path: string, init?: RequestInit): Promise<T> { return request<T>(path, init); }
