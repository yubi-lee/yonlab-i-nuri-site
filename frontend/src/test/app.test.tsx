import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import App from "../App";

test("renders the search-led home hero", () => {
  render(<QueryClientProvider client={new QueryClient()}><MemoryRouter><App /></MemoryRouter></QueryClientProvider>);
  expect(screen.getByRole("heading", { name: /배우고, 실험하고/ })).toBeInTheDocument();
  expect(screen.getByRole("search")).toBeInTheDocument();
});
test("admin surface exposes all managed entity sections", () => {
  localStorage.setItem("session", JSON.stringify({
    access_token: "token",
    refresh_token: "refresh",
    user: { id: "a1", email: "admin@example.com", name: "Admin", role: "admin" }
  }));
  render(<QueryClientProvider client={new QueryClient()}><MemoryRouter initialEntries={["/admin"]}><App /></MemoryRouter></QueryClientProvider>);
  for (const name of ["자료", "공지", "인사이트", "FAQ", "카테고리", "태그", "문의", "사용자"]) {
    expect(screen.getByRole("tab", { name })).toBeInTheDocument();
  }
  localStorage.clear();
});
