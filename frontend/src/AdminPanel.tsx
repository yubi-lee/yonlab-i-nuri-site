import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "./client";

const entities = [
  ["resources", "자료"], ["notices", "공지"], ["articles", "인사이트"], ["faqs", "FAQ"],
  ["categories", "카테고리"], ["tags", "태그"], ["inquiries", "문의"], ["users", "사용자"],
] as const;

type Row = Record<string, string | number | boolean | null>;
type Page = { items: Row[]; total: number; page: number; page_size: number };

export default function AdminPanel() {
  const [kind, setKind] = useState<(typeof entities)[number][0]>("resources");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [feedback, setFeedback] = useState("");
  const queryClient = useQueryClient();
  const list = useQuery({ queryKey: ["admin", kind, q, page], queryFn: () => api<Page>(`/admin/${kind}?q=${encodeURIComponent(q)}&page=${page}&page_size=20`) });
  const categories = useQuery({ queryKey: ["admin", "categories", "options"], queryFn: () => api<Page>("/admin/categories?page_size=100"), enabled: kind === "resources" });
  const invalidate = () => queryClient.invalidateQueries({ queryKey: ["admin"] });
  const create = useMutation({ mutationFn: (data: Row) => api<Row>(`/admin/${kind}`, { method: "POST", body: JSON.stringify(data) }), onSuccess: () => { setFeedback("저장했습니다."); invalidate(); }, onError: (e) => setFeedback(e.message) });
  const update = useMutation({ mutationFn: ({ id, data }: { id: string; data: Row }) => api<Row>(`/admin/${kind}/${id}`, { method: "PATCH", body: JSON.stringify(data) }), onSuccess: () => { setFeedback("변경했습니다."); invalidate(); }, onError: (e) => setFeedback(e.message) });
  const remove = useMutation({ mutationFn: (id: string) => api<void>(`/admin/${kind}/${id}`, { method: "DELETE" }), onSuccess: () => { setFeedback("삭제 또는 보관 처리했습니다."); invalidate(); }, onError: (e) => setFeedback(e.message) });

  const fields = useMemo(() => {
    if (kind === "categories" || kind === "tags") return [["name", "이름"], ["slug", "슬러그"]];
    if (kind === "faqs") return [["question", "질문"], ["answer", "답변"]];
    if (kind === "notices") return [["title", "제목"], ["body", "본문"]];
    if (kind === "articles") return [["title", "제목"], ["summary", "요약"], ["body", "본문"]];
    if (kind === "resources") return [["title", "제목"], ["summary", "요약"], ["body", "본문"], ["audience", "대상"], ["resource_type", "자료 유형"]];
    return [];
  }, [kind]);

  function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const values = Object.fromEntries(new FormData(event.currentTarget)) as Row;
    if (kind === "resources") Object.assign(values, { status: "draft", tag_ids: [] });
    if (["notices", "articles", "faqs"].includes(kind)) values.status = "draft";
    create.mutate(values);
    event.currentTarget.reset();
  }

  function edit(row: Row) {
    const field = kind === "faqs" ? "question" : kind === "categories" || kind === "tags" ? "name" : kind === "users" ? "role" : kind === "inquiries" ? "status" : "title";
    const value = window.prompt(`${field} 새 값`, String(row[field] ?? ""));
    if (value !== null) update.mutate({ id: String(row.id), data: { [field]: value } });
  }

  return <section className="container section page admin-page">
    <span className="eyebrow">ADMIN CMS</span><h1>운영 대시보드</h1>
    <div className="admin-tabs" role="tablist">{entities.map(([value, label]) => <button type="button" role="tab" aria-selected={kind === value} key={value} onClick={() => { setKind(value); setPage(1); setFeedback(""); }}>{label}</button>)}</div>
    <div className="filter"><input aria-label="관리자 목록 검색" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} placeholder="검색어"/></div>
    {feedback && <p role="status" className={feedback.includes("했습니다") ? "success" : "error"}>{feedback}</p>}
    {fields.length > 0 && <form className="admin-form" onSubmit={submit}>
      {fields.map(([name, label]) => <label key={name}>{label}<input name={name} required /></label>)}
      {kind === "resources" && <label>카테고리<select name="category_id" required>{categories.data?.items.map((row) => <option key={String(row.id)} value={String(row.id)}>{String(row.name)}</option>)}</select></label>}
      <button className="button" disabled={create.isPending}>새 항목 저장</button>
    </form>}
    {list.isLoading ? <div className="state">목록을 불러오는 중입니다.</div> : list.error ? <div className="state error">{list.error.message}</div> : !list.data?.items.length ? <div className="state">항목이 없습니다.</div> : <div className="admin-table-wrap"><table><thead><tr><th>내용</th><th>상태</th><th>작업</th></tr></thead><tbody>{list.data.items.map((row) => <tr key={String(row.id)}><td><strong>{String(row.title ?? row.question ?? row.name ?? row.email ?? row.subject)}</strong><small>{String(row.slug ?? row.summary ?? "")}</small></td><td>{String(row.status ?? row.role ?? row.is_active ?? "")}</td><td><button onClick={() => edit(row)}>수정</button>{!["users", "inquiries"].includes(kind) && <button onClick={() => window.confirm("정말 처리할까요?") && remove.mutate(String(row.id))}>삭제</button>}</td></tr>)}</tbody></table></div>}
    <div className="pagination"><button disabled={page === 1} onClick={() => setPage(page - 1)}>이전</button><span>{page} / {Math.max(1, Math.ceil((list.data?.total ?? 0) / 20))}</span><button disabled={page * 20 >= (list.data?.total ?? 0)} onClick={() => setPage(page + 1)}>다음</button></div>
  </section>;
}
