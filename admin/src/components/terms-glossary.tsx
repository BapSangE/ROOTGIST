"use client";
import { useEffect, useState } from "react";
import type { Envelope, PageResult, TermRow } from "@/lib/domain/contracts";
import { logout } from "@/lib/server/login-actions";
import { useAdminFixture } from "./admin-shell";
import { SearchBox, StatePanel, Status, formatDate, useQuery } from "./shared";

type TermList = PageResult<TermRow> & Envelope;

const kinds = [
  ["sense", "사전 의미"],
  ["candidate", "후보"],
] as const;

// 전체 용어 모음: 검수를 끝낸 용어(기본)와 나머지를 한눈에 훑는 읽기 전용 목록. 행을 누르면 검수 화면에서 그 용어를 연다.
// 목록은 검수 화면과 같은 /terms API(상태·종류·검색 필터, 50개씩)를 이어 받는다.
export function TermsGlossary() {
  const fixture = useAdminFixture();
  const { params, change } = useQuery();
  const type = params.get("type") ?? "sense";
  const filter = params.get("filter") ?? "approved";
  const query = params.get("query") ?? "";
  const base = new URLSearchParams({ type, filter, ...(query ? { query } : {}) }).toString();
  const [pages, setPages] = useState<{ base: string; rows: TermRow[]; total: number; next: string | null } | null>(null);
  const [cursor, setCursor] = useState<string | null>(null); // 「더 보기」로 요청한 다음 페이지(조건이 바뀌면 비운다)
  const [error, setError] = useState<{ key: string; message: string } | null>(null);
  const [version, setVersion] = useState(0);
  const key = `${base}|${cursor ?? ""}|${version}`;
  const [loadedKey, setLoadedKey] = useState("");
  const loading = loadedKey !== key && error?.key !== key;

  useEffect(() => {
    const controller = new AbortController();
    const url = `/api/admin/v1/terms?${base}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`;
    fetch(url, { cache: "no-store", signal: controller.signal })
      .then(async (response) => {
        const body = (await response.json()) as TermList & { error?: { message?: string } };
        if (!response.ok) throw new Error(body.error?.message ?? "데이터를 불러오지 못했어요.");
        setPages((prev) => ({
          base,
          rows: cursor && prev?.base === base ? [...prev.rows, ...body.rows] : body.rows,
          total: body.total,
          next: body.next_cursor,
        }));
        setLoadedKey(key);
      })
      .catch((e) => {
        if (!controller.signal.aborted)
          setError({ key, message: e instanceof Error ? e.message : "데이터를 불러오지 못했어요." });
      });
    return () => controller.abort();
  }, [base, cursor, key]);

  const rows = pages?.base === base ? pages.rows : [];
  const reset = (values: Record<string, string | null>) => {
    setCursor(null);
    change(values);
  };

  return (
    <>
      <header className="app-header">
        <a href="/admin/terms" className="brand" aria-label="ROOTGIST 용어 검수">
          ROOTGIST
          <span className="divider" />
          <span className="brand-sub">전체 용어</span>
        </a>
        <span className="prototype">{fixture ? "가상 데이터" : "실제 데이터 · 조회"}</span>
        <div className="header-actions">
          <a className="quiet glossary-link" href="/admin/terms">
            용어 검수
          </a>
          {!fixture && (
            <form action={logout}>
              <button className="quiet logout">로그아웃</button>
            </form>
          )}
        </div>
      </header>
      <main className="glossary" id="content" tabIndex={-1} aria-label="전체 용어 모음">
        <div className="glossary-inner">
          <div className="glossary-head">
            <h1>
              전체 용어 <span className="count">{pages?.base === base ? pages.total : "—"}</span>
            </h1>
            <p>검수를 끝낸 용어를 기본으로 보여 줘요. 누르면 검수 화면에서 그 용어를 열어요.</p>
          </div>
          <div className="glossary-controls">
            <SearchBox label="용어 검색" query={query} onSearch={(q) => reset({ query: q || null })} />
            <div className="glossary-kinds" role="group" aria-label="종류">
              {kinds.map(([value, label]) => (
                <button key={value} aria-pressed={type === value} onClick={() => reset({ type: value })}>
                  {label}
                </button>
              ))}
            </div>
            <label className="filter">
              <span>상태</span>
              <select value={filter} onChange={(e) => reset({ filter: e.target.value })}>
                <option value="approved">검수 완료</option>
                <option value="all">전체</option>
                <option value="pending">검토 필요</option>
                <option value="deferred">수정 필요</option>
                <option value="rejected">반려</option>
              </select>
            </label>
          </div>
          {error?.key === key || (loading && !rows.length) ? (
            <StatePanel
              loading={error?.key !== key}
              error={error?.key === key ? error.message : null}
              retry={() => setVersion((v) => v + 1)}
            />
          ) : !rows.length ? (
            <StatePanel empty={query ? "검색 결과가 없어요" : "해당하는 용어가 없어요"} />
          ) : (
            <ol className="glossary-list">
              {rows.map((row) => (
                <li key={`${row.type}:${row.id}`}>
                  <a
                    className="glossary-row"
                    href={`/admin/terms?${new URLSearchParams({ type: row.type, id: row.id, filter: "all" })}`}
                  >
                    <span className="glossary-term">
                      <span className="row-title">{row.term}</span>
                      <span className="row-ko">{row.canonical_ko ?? "한국어 표기 없음"}</span>
                    </span>
                    <span className="glossary-def">{row.definition || "정의 없음"}</span>
                    <span className="glossary-meta">
                      <Status status={row.status} />
                      <span>{row.paper_count ? `논문 ${row.paper_count}편` : "논문 연결 없음"}</span>
                      {row.reviewed_at && <span>{formatDate(row.reviewed_at)}</span>}
                    </span>
                  </a>
                </li>
              ))}
            </ol>
          )}
          {pages?.base === base && pages.next && (
            <button
              className="button secondary glossary-more"
              disabled={loading}
              aria-busy={loading}
              onClick={() => setCursor(pages.next)}
            >
              {loading ? "불러오는 중…" : `더 보기 (${rows.length}/${pages.total})`}
            </button>
          )}
        </div>
      </main>
    </>
  );
}
