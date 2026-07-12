import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { BookOpen, Menu, Search, Sparkles, X } from "lucide-react";
import { Link, Navigate, Route, Routes, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { api, getSession, setSession, type Resource, type User } from "./client";
import AdminPanel from "./AdminPanel";
import { MemberDetail, MemberHome } from "./MemberPages";

const topics = ["AI 수업 설계", "온디바이스 AI", "디지털 리터러시", "교사 지원", "안전·윤리", "YOnLab 소식"];

function Layout({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  return <><header><div className="container nav"><Link className="wordmark" to="/">YOnLearn Hub</Link><button className="menu" aria-label="메뉴 열기" onClick={() => setOpen(!open)}>{open ? <X /> : <Menu />}</button><nav className={open ? "open" : ""}><Link to="/about">소개</Link><Link to="/resources">자료실</Link><Link to="/search">통합검색</Link><Link to="/inquiry">문의</Link><Link className="login-link" to="/login">로그인</Link></nav></div></header><main>{children}</main><footer><div className="container footer-grid"><div><strong>YOnLearn Hub</strong><p>교육과 AI를 연결하는 YOnLab의 가상 데모 포털입니다.</p></div><div><strong>탐색</strong><Link to="/resources">자료실</Link><Link to="/search">통합검색</Link></div><div><strong>지원</strong><Link to="/inquiry">문의하기</Link></div><div><strong>안내</strong><p>운영 전 개인정보 정책 검토가 필요합니다.</p></div></div></footer></>;
}

function SearchBox({ initial = "" }: { initial?: string }) {
  const [q, setQ] = useState(initial); const nav = useNavigate();
  return <form className="search-box" role="search" onSubmit={(e) => { e.preventDefault(); if (q.trim()) nav(`/search?q=${encodeURIComponent(q)}`); }}><Search /><label className="sr-only" htmlFor="site-search">자료 검색</label><input id="site-search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="어떤 AI 교육 자료가 필요하신가요?" /><button>검색</button></form>;
}

function Card({ item }: { item: Resource }) {
  return <article className="card"><div className="card-icon"><BookOpen /></div><span>{item.category.name} · {item.resource_type}</span><h3><Link to={`/resources/${item.id}`}>{item.title}</Link></h3><p>{item.summary}</p><div className="tags">{item.tags.slice(0,2).map(t => <small key={t.slug}>#{t.name}</small>)}</div></article>;
}
const State = ({ children }: { children: React.ReactNode }) => <div className="state" role="status">{children}</div>;

function Home() {
  const query = useQuery({ queryKey:["featured"], queryFn:()=>api<{items:Resource[]}>("/resources?page_size=4") });
  return <><section className="hero"><div className="ambient" /><div className="container hero-inner"><span className="eyebrow"><Sparkles size={16}/> 교육과 AI의 다음 장면</span><h1>배우고, 실험하고,<br/><em>현장에 바로 적용하세요.</em></h1><p>신뢰할 수 있는 AI 교육 자료를 대상과 주제에 맞게 빠르게 찾는 YOnLab의 지식 허브입니다.</p><SearchBox/><div className="quick">{topics.slice(0,4).map(x=><Link key={x} to={`/search?q=${x}`}>#{x}</Link>)}</div></div></section><section className="container section"><div className="section-head"><div><span className="eyebrow">CURATED</span><h2>지금 추천하는 자료</h2></div><Link to="/resources">전체 자료 →</Link></div>{query.isLoading ? <State>자료를 불러오는 중입니다.</State> : query.data?.items.length ? <div className="cards">{query.data.items.map(x=><Card key={x.id} item={x}/>)}</div> : <State>아직 공개된 자료가 없습니다.</State>}</section><section className="topics"><div className="container section"><span className="eyebrow">EXPLORE</span><h2>필요한 주제로 바로 시작하세요</h2><div className="topic-grid">{topics.map((x,i)=><Link key={x} to={`/search?q=${x}`}><span>0{i+1}</span><strong>{x}</strong><b>→</b></Link>)}</div></div></section><section className="container cta"><div><h2>우리 조직에 맞는 AI 교육이 필요하신가요?</h2><p>현장의 목표와 제약을 이해하고 실행 가능한 학습 경험을 함께 설계합니다.</p></div><Link className="button light" to="/inquiry">YOnLab에 문의하기</Link></section></>;
}

function Resources() {
  const [q,setQ]=useState(""); const query=useQuery({queryKey:["resources",q],queryFn:()=>api<{items:Resource[];total:number}>(`/resources?q=${encodeURIComponent(q)}`)});
  return <section className="container section page"><span className="eyebrow">RESOURCE LIBRARY</span><h1>자료실</h1><p className="lead">대상과 주제에 맞는 가상 교육 자료를 살펴보세요.</p><div className="filter"><Search/><input aria-label="자료실 검색" value={q} onChange={e=>setQ(e.target.value)} placeholder="자료 제목이나 설명 검색"/></div>{query.data?.items.length ? <><p>총 {query.data.total}개</p><div className="cards">{query.data.items.map(x=><Card key={x.id} item={x}/>)}</div></> : <State>조건에 맞는 자료가 없습니다.</State>}</section>;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
function Detail() {
  const {id}=useParams(); const query=useQuery({queryKey:["resource",id],queryFn:()=>api<Resource>(`/resources/${id}`)});
  if (!query.data) return <State>자료를 불러오는 중입니다.</State>;
  return <article className="container detail"><Link to="/resources">← 자료실로</Link><span className="eyebrow">{query.data.category.name}</span><h1>{query.data.title}</h1><p className="lead">{query.data.summary}</p><div className="prose">{query.data.body}</div></article>;
}

function SearchPage() {
  const [params]=useSearchParams(); const q=params.get("q") ?? ""; const query=useQuery({queryKey:["search",q],queryFn:()=>api<{total:number;items:{id:string;type:string;title:string;excerpt:string}[]}>(`/search?q=${encodeURIComponent(q)}`),enabled:!!q});
  return <section className="container section page"><h1>통합검색</h1><SearchBox initial={q}/>{query.data?.items.length ? <><p>‘{q}’ 검색 결과 {query.data.total}개</p><div className="results">{query.data.items.map(x=><article key={x.type+x.id}><small>{x.type}</small><h2>{x.title}</h2><p>{x.excerpt}</p></article>)}</div></> : <State>{q ? "검색 결과가 없습니다." : "자료, 공지, 인사이트, FAQ를 한 번에 검색합니다."}</State>}</section>;
}

function Login() {
  const nav=useNavigate(); const mutation=useMutation({mutationFn:(data:object)=>api<{access_token:string;refresh_token:string;user:User}>("/auth/login",{method:"POST",body:JSON.stringify(data)}),onSuccess:data=>{setSession(data);nav(data.user.role==="admin"?"/admin":"/mypage");}});
  return <section className="auth"><div><h1>다시 만나 반가워요</h1><form onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);mutation.mutate({email:f.get("email"),password:f.get("password")});}}><label>이메일<input name="email" type="email" required/></label><label>비밀번호<input name="password" type="password" minLength={10} required/></label>{mutation.error&&<p className="error">{mutation.error.message}</p>}<button className="button">로그인</button><Link to="/register">회원가입</Link></form></div></section>;
}

function Register() {
  const nav=useNavigate(); const mutation=useMutation({mutationFn:(data:object)=>api<{access_token:string;refresh_token:string;user:User}>("/auth/register",{method:"POST",body:JSON.stringify(data)}),onSuccess:data=>{setSession(data);nav("/mypage");}});
  return <section className="auth"><div><h1>배움의 흐름을 저장하세요</h1><form onSubmit={e=>{e.preventDefault();mutation.mutate(Object.fromEntries(new FormData(e.currentTarget)));}}><label>이름<input name="name" minLength={2} required/></label><label>이메일<input name="email" type="email" required/></label><label>비밀번호<input name="password" type="password" minLength={10} required/></label><button className="button">회원가입</button></form></div></section>;
}

function Inquiry() {
  const mutation=useMutation({mutationFn:(data:object)=>api("/inquiries",{method:"POST",body:JSON.stringify(data)})});
  if(mutation.isSuccess)return <section className="container section page"><State>문의가 접수되었습니다.</State></section>;
  return <section className="container section page narrow"><h1>무엇을 함께 해결할까요?</h1><form className="form" onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);mutation.mutate({email:f.get("email"),subject:f.get("subject"),message:f.get("message"),privacy_agreed:f.get("privacy")==="on"});}}><label>이메일<input name="email" type="email" required/></label><label>문의 제목<input name="subject" required/></label><label>문의 내용<textarea name="message" minLength={10} rows={7} required/></label><label className="check"><input name="privacy" type="checkbox" required/>답변을 위한 이메일 수집에 동의합니다.</label><button className="button">문의 보내기</button></form></section>;
}

function Guard({admin=false,children}:{admin?:boolean;children:React.ReactNode}) { const user=getSession()?.user;return !user||admin&&user.role!=="admin"?<Navigate to="/login"/>:<>{children}</>; }
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const MyPage=()=> <section className="container section page"><h1>마이페이지</h1><State>저장한 관심 자료와 문의 내역이 여기에 표시됩니다.</State></section>;
// eslint-disable-next-line @typescript-eslint/no-unused-vars
function Admin(){const q=useQuery({queryKey:["admin"],queryFn:()=>api<Record<string,number>>("/admin/dashboard")});return <section className="container section page"><h1>운영 대시보드</h1><div className="stats">{Object.entries(q.data??{}).map(([k,v])=><div key={k}><span>{k}</span><strong>{v}</strong></div>)}</div></section>;}
const About=()=> <section className="container section page narrow"><h1>교육과 AI 사이,<br/>실행 가능한 지식을 만듭니다.</h1><p className="lead">교육자와 학습자가 검증 가능한 AI 활용 방법을 빠르게 탐색하도록 설계한 YOnLab의 포털입니다.</p></section>;

export default function App(){return <Layout><Routes><Route path="/" element={<Home/>}/><Route path="/about" element={<About/>}/><Route path="/resources" element={<Resources/>}/><Route path="/resources/:id" element={<MemberDetail/>}/><Route path="/search" element={<SearchPage/>}/><Route path="/login" element={<Login/>}/><Route path="/register" element={<Register/>}/><Route path="/inquiry" element={<Inquiry/>}/><Route path="/mypage" element={<Guard><MemberHome/></Guard>}/><Route path="/admin" element={<Guard admin><AdminPanel/></Guard>}/><Route path="*" element={<Navigate to="/"/>}/></Routes></Layout>;}
