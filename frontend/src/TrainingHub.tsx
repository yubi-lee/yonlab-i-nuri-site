import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { api, getSession } from "./client";

type Organization = { id: string; name: string; slug: string; owner_id: string; status: string };
type DiagnosisSession = {
  id: string;
  status: string;
  goal: string;
  current_sequence: number;
  result?: { status: string; overall_score_microunit?: number | null } | null;
};
type LearningPath = { id: string; title: string; description: string; difficulty: string };
type DocumentItem = { id: string; title: string; status: string; latest_version_id: string | null };

function Notice({ children }: { children: React.ReactNode }) {
  return <p className="state" role="status">{children}</p>;
}

export default function TrainingHub() {
  const session = getSession();
  const [organizationId, setOrganizationId] = useState("");
  const [diagnosis, setDiagnosis] = useState<DiagnosisSession | null>(null);
  const [goal, setGoal] = useState("수업 설계 역량 진단");
  const [turnText, setTurnText] = useState("");
  const [documentText, setDocumentText] = useState("");
  const [documentTitle, setDocumentTitle] = useState("");
  const [searchText, setSearchText] = useState("");

  const organizations = useQuery<Organization[]>({
    queryKey: ["organizations"],
    queryFn: () => api<Organization[]>("/organizations"),
  });
  const activeOrganizationId = organizationId || organizations.data?.[0]?.id || "";
  const paths = useQuery<{ items: LearningPath[] }>({
    queryKey: ["learning-paths"],
    queryFn: () => api<{ items: LearningPath[] }>("/learning/paths"),
  });
  const documents = useQuery<{ items: DocumentItem[] }>({
    queryKey: ["documents", activeOrganizationId],
    queryFn: () => api<{ items: DocumentItem[] }>(`/documents?organization_id=${encodeURIComponent(activeOrganizationId)}`),
    enabled: Boolean(activeOrganizationId),
  });
  const knowledge = useQuery<{
    items: { document_title: string; content: string; citations: { locator: string }[] }[];
    no_answer: boolean;
  }>({
    queryKey: ["knowledge", activeOrganizationId, searchText],
    queryFn: () => api(`/knowledge/search?organization_id=${encodeURIComponent(activeOrganizationId)}&q=${encodeURIComponent(searchText)}`),
    enabled: Boolean(activeOrganizationId && searchText.trim()),
  });
  const createOrganization = useMutation({
    mutationFn: (name: string) => api<Organization>("/organizations", { method: "POST", body: JSON.stringify({ name }) }),
    onSuccess: (item) => { setOrganizationId(item.id); void organizations.refetch(); },
  });
  const createDiagnosis = useMutation({
    mutationFn: () => api<DiagnosisSession>("/diagnosis/sessions", { method: "POST", body: JSON.stringify({ organization_id: activeOrganizationId, goal }) }),
    onSuccess: setDiagnosis,
  });
  const addTurn = useMutation({
    mutationFn: () => api(`/diagnosis/sessions/${diagnosis?.id}/turns`, { method: "POST", body: JSON.stringify({ content: turnText, evidence: [] }) }),
    onSuccess: () => setTurnText(""),
  });
  const completeDiagnosis = useMutation({
    mutationFn: () => api<DiagnosisSession>(`/diagnosis/sessions/${diagnosis?.id}/complete`, { method: "POST" }),
    onSuccess: setDiagnosis,
  });
  const enroll = useMutation({
    mutationFn: (pathId: string) => api("/learning/enrollments", { method: "POST", body: JSON.stringify({ organization_id: activeOrganizationId, path_id: pathId }) }),
  });
  const createDocument = useMutation({
    mutationFn: () => api<DocumentItem>("/documents", { method: "POST", body: JSON.stringify({ organization_id: activeOrganizationId, title: documentTitle, mime_type: "text/plain", content: documentText }) }),
    onSuccess: () => { setDocumentText(""); setDocumentTitle(""); void documents.refetch(); },
  });
  const processDocument = useMutation({
    mutationFn: (id: string) => api(`/documents/${id}/process`, { method: "POST" }),
    onSuccess: () => void documents.refetch(),
  });

  if (!session) return <section className="container section page"><Notice><Link to="/login">로그인</Link> 후 진단과 학습을 시작할 수 있습니다.</Notice></section>;

  return <section className="container section page training-hub">
    <span className="eyebrow">AI TRAINING PLATFORM</span>
    <h1>진단에서 학습까지</h1>
    <p className="lead">조직의 맥락을 선택하고, 근거가 남는 진단과 학습 흐름을 시작하세요.</p>

    <section className="panel" aria-labelledby="organization-heading">
      <h2 id="organization-heading">1. 조직 공간</h2>
      {organizations.data?.length ? <label>조직 선택<select value={activeOrganizationId} onChange={(event) => setOrganizationId(event.target.value)}>{organizations.data.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label> : <CreateOrganization onCreate={(name) => createOrganization.mutate(name)} />}
      {createOrganization.error && <p className="error">조직을 만들지 못했습니다.</p>}
    </section>

    <section className="panel" aria-labelledby="diagnosis-heading">
      <h2 id="diagnosis-heading">2. 역량 진단</h2>
      {!diagnosis ? <form className="form-inline" onSubmit={(event) => { event.preventDefault(); createDiagnosis.mutate(); }}><label>진단 목표<input value={goal} onChange={(event) => setGoal(event.target.value)} required /></label><button className="button" disabled={!activeOrganizationId || createDiagnosis.isPending}>진단 시작</button></form> : <div><p>상태: {diagnosis.status} · 응답 {diagnosis.current_sequence}개</p>{diagnosis.status === "in_progress" && <form className="form" onSubmit={(event) => { event.preventDefault(); addTurn.mutate(); }}><label>현장 응답<textarea value={turnText} onChange={(event) => setTurnText(event.target.value)} minLength={1} rows={4} required /></label><button className="button">응답 저장</button></form>}{diagnosis.status === "in_progress" && <button className="button secondary" onClick={() => completeDiagnosis.mutate()}>진단 완료</button>}{diagnosis.result && <Notice>진단 결과: {diagnosis.result.status} · 점수 {diagnosis.result.overall_score_microunit ?? 0}</Notice>}</div>}
    </section>

    <section className="panel" aria-labelledby="learning-heading">
      <h2 id="learning-heading">3. 추천 학습</h2>
      <div className="cards">{paths.data?.items.map((path) => <article className="card" key={path.id}><h3>{path.title}</h3><p>{path.description}</p><small>{path.difficulty}</small><button className="button" onClick={() => enroll.mutate(path.id)} disabled={!activeOrganizationId}>학습 등록</button></article>)}</div>
    </section>

    <section className="panel" aria-labelledby="document-heading">
      <h2 id="document-heading">4. 근거 문서</h2>
      <form className="form" onSubmit={(event) => { event.preventDefault(); createDocument.mutate(); }}><label>문서 제목<input value={documentTitle} onChange={(event) => setDocumentTitle(event.target.value)} required /></label><label>문서 내용<textarea value={documentText} onChange={(event) => setDocumentText(event.target.value)} rows={4} required /></label><button className="button" disabled={!activeOrganizationId}>문서 등록</button></form>
      <ul className="plain-list">{documents.data?.items.map((document) => <li key={document.id}><span>{document.title} · {document.status}</span><button className="button secondary" onClick={() => processDocument.mutate(document.id)} disabled={document.status === "processed"}>처리</button></li>)}</ul>
      <label>근거 검색<input value={searchText} onChange={(event) => setSearchText(event.target.value)} placeholder="검색어를 입력하세요" /></label>
      {knowledge.data?.no_answer && <Notice>확인 가능한 근거가 없습니다.</Notice>}
      <div className="results">{knowledge.data?.items.map((item) => <article key={`${item.document_title}-${item.citations[0]?.locator}`}><small>{item.document_title} · {item.citations[0]?.locator}</small><p>{item.content}</p></article>)}</div>
    </section>
  </section>;
}

function CreateOrganization({ onCreate }: { onCreate: (name: string) => void }) {
  const [name, setName] = useState("");
  return <form className="form-inline" onSubmit={(event) => { event.preventDefault(); onCreate(name); }}><label>조직명<input value={name} onChange={(event) => setName(event.target.value)} minLength={2} required /></label><button className="button">조직 만들기</button></form>;
}
