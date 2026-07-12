import { useMutation, useQuery } from "@tanstack/react-query";
import { Bookmark } from "lucide-react";
import { Link, useParams } from "react-router-dom";
import { api, type Resource } from "./client";

export function MemberDetail() {
  const { id } = useParams();
  const resource = useQuery({ queryKey: ["resource", id], queryFn: () => api<Resource>(`/resources/${id}`) });
  const bookmark = useMutation({ mutationFn: () => api(`/me/bookmarks/${id}`, { method: "POST" }) });
  if (resource.isLoading) return <div className="state">자료를 불러오는 중입니다.</div>;
  if (resource.error || !resource.data) return <div className="state error">자료를 찾을 수 없습니다.</div>;
  return <article className="container detail"><Link to="/resources">← 자료실로</Link><span className="eyebrow">{resource.data.category.name}</span><h1>{resource.data.title}</h1><p className="lead">{resource.data.summary}</p><button className="button" onClick={() => bookmark.mutate()} disabled={bookmark.isPending}><Bookmark size={18}/>{bookmark.isSuccess ? "저장됨" : "관심 자료 저장"}</button>{bookmark.error && <p className="error">{bookmark.error.message}</p>}<hr/><div className="prose">{resource.data.body}</div></article>;
}

export function MemberHome() {
  const bookmarks = useQuery({ queryKey: ["bookmarks"], queryFn: () => api<{ id: string; resource: { id: string; title: string; summary: string } }[]>("/me/bookmarks") });
  const inquiries = useQuery({ queryKey: ["my-inquiries"], queryFn: () => api<{ id: string; subject: string; status: string; created_at: string }[]>("/me/inquiries") });
  return <section className="container section page"><span className="eyebrow">MY LEARNING</span><h1>마이페이지</h1><h2>관심 자료</h2>{bookmarks.isLoading ? <div className="state">불러오는 중입니다.</div> : bookmarks.data?.length ? bookmarks.data.map((item) => <article className="row" key={item.id}><div><h3>{item.resource.title}</h3><p>{item.resource.summary}</p></div><Link to={`/resources/${item.resource.id}`}>보기</Link></article>) : <div className="state">저장한 관심 자료가 없습니다.</div>}<h2>내 문의</h2>{inquiries.isLoading ? <div className="state">불러오는 중입니다.</div> : inquiries.data?.length ? inquiries.data.map((item) => <article className="row" key={item.id}><div><h3>{item.subject}</h3><p>상태: {item.status}</p></div></article>) : <div className="state">등록한 문의가 없습니다.</div>}</section>;
}
