import { afterEach, expect, test, vi } from "vitest";
import { api, setSession } from "../client";

afterEach(() => {
  vi.restoreAllMocks();
  localStorage.clear();
});

test("refreshes an expired access token and retries the original request", async () => {
  setSession({ access_token: "expired", refresh_token: "refresh-1", user: { id: "u1", email: "user@example.com", name: "User", role: "user" } });
  const fetchMock = vi.spyOn(globalThis, "fetch")
    .mockResolvedValueOnce(new Response(JSON.stringify({ detail: "expired" }), { status: 401, headers: { "Content-Type": "application/json" } }))
    .mockResolvedValueOnce(new Response(JSON.stringify({ access_token: "fresh", refresh_token: "refresh-2", user: { id: "u1", email: "user@example.com", name: "User", role: "user" } }), { status: 200, headers: { "Content-Type": "application/json" } }))
    .mockResolvedValueOnce(new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "Content-Type": "application/json" } }));

  await expect(api<{ ok: boolean }>("/me")).resolves.toEqual({ ok: true });
  expect(fetchMock).toHaveBeenCalledTimes(3);
  expect(JSON.parse(localStorage.getItem("session")!).access_token).toBe("fresh");
});

test("clears session when refresh token is rejected", async () => {
  setSession({ access_token: "expired", refresh_token: "bad", user: { id: "u1", email: "user@example.com", name: "User", role: "user" } });
  vi.spyOn(globalThis, "fetch")
    .mockResolvedValueOnce(new Response("{}", { status: 401 }))
    .mockResolvedValueOnce(new Response("{}", { status: 401 }));

  await expect(api("/me")).rejects.toThrow();
  expect(localStorage.getItem("session")).toBeNull();
});
