"use client";
import Link from "next/link";
import { listQuery } from "@/lib/domain/query";
import { useEffect, useState } from "react";
import type {
  Dashboard,
  Envelope,
  PageResult,
  Paper,
  News,
  Model,
  Notice,
  Source,
  Sense,
  Revisioned,
  TermRow,
} from "@/lib/domain/contracts";
import { projectPaperForPreview, latexDisplay } from "@/lib/domain/display";
import {
  Badge,
  Status,
  PageIntro,
  Icon,
  StatePanel,
  SearchBox,
  ReadOnlyActions,
  ExternalLink,
  HighlightText,
  formatDate,
  useResource,
  useQuery,
  ScrollList,
} from "./shared";
type Detail<T> = Revisioned<T> &
  Envelope & { all_senses?: Sense[]; show_ai_reviewed_terms?: boolean };
export function DashboardScreen() {
  const result = useResource<Dashboard>("/api/admin/v1/dashboard");
  const d = result.data;
  return (
    <>
      <PageIntro
        eyebrow="EDITORIAL OVERVIEW"
        title="대시보드"
        description="오늘 확인할 콘텐츠와 운영 연결 상태를 살펴보세요."
      >
        <button className="button secondary" onClick={result.retry}>
          <Icon name="refresh" size={16} />
          새로 불러오기
        </button>
      </PageIntro>
      {!d ? (
        <StatePanel
          loading={result.loading}
          error={result.error}
          retry={result.retry}
        />
      ) : (
        <>
          <div className="overview-grid">
            {[
              [
                d.counts.risks,
                "적용 위치 확인",
                "용어가 번역문에 정확히 연결됐는지 확인해요.",
                "/admin/terms?type=occurrence&filter=risks",
              ],
              [
                d.counts.terms,
                "용어 검토 대기",
                "사전 의미와 추출 후보를 구분해 검토해요.",
                "/admin/terms?type=sense&filter=pending",
              ],
              [
                d.counts.papers,
                "조회 가능한 논문",
                "사람 승인 상태와 AI 처리 상태는 별개예요.",
                "/admin/papers",
              ],
              [
                d.counts.news,
                "공식 소식",
                "요약과 수집된 근거를 함께 확인해요.",
                "/admin/news",
              ],
            ].map(([value, label, help, href]) => (
              <Link
                href={String(href)}
                className="metric-card"
                key={String(label)}
              >
                <span>{label}</span>
                <strong>{value}</strong>
                <p>{help}</p>
                <Icon name="arrow" size={18} />
              </Link>
            ))}
          </div>
          <div className="dashboard-grid">
            <section className="panel">
              <div className="panel-heading">
                <h2>먼저 확인할 적용 위치</h2>
                <Link href="/admin/terms" className="text-link">
                  전체 보기 →
                </Link>
              </div>
              <div className="priority-list">
                {d.priorities.length ? (
                  d.priorities.map((row) => <Priority key={row.id} row={row} />)
                ) : (
                  <StatePanel empty="계산된 적용 위험이 없어요" />
                )}
              </div>
            </section>
            <section className="panel">
              <div className="panel-heading">
                <h2>배치 · 콘텐츠 신선도</h2>
                <Badge>부분 연결</Badge>
              </div>
              <div className="summary-content">
                <div className="info-row">
                  <span>예약된 수집 시각</span>
                  <strong>KST 02:17</strong>
                </div>
                <div className="info-row">
                  <span>마지막 실행</span>
                  <strong>연동 필요</strong>
                </div>
                <div className="info-row">
                  <span>AI 처리 실패</span>
                  <strong>{d.counts.failed}건</strong>
                </div>
                <div className="callout">
                  <strong>{d.operations.label}</strong>
                  <p>
                    수집 시각과 전체 배치 성공은 달라요. 실행별 결과를 연결한 뒤
                    표시해요.
                  </p>
                </div>
                <Link href="/admin/operations" className="text-link">
                  운영 상태 확인 →
                </Link>
              </div>
            </section>
            <section className="panel">
              <div className="panel-heading">
                <h2>최근 수집 콘텐츠</h2>
                <Badge>발행일 기준</Badge>
              </div>
              {d.recent.map((row) => (
                <Link
                  className="recent-row"
                  key={`${row.kind}:${row.id}`}
                  href={`${row.kind === "논문" ? "/admin/papers" : "/admin/news"}?id=${encodeURIComponent(row.id)}`}
                >
                  <div>
                    <span className="micro muted">{row.kind}</span>
                    <strong>{row.title}</strong>
                  </div>
                  <span className="micro muted">{formatDate(row.at)}</span>
                </Link>
              ))}
            </section>
            <section className="panel">
              <div className="panel-heading">
                <h2>현재 검토 범위</h2>
              </div>
              <div className="summary-content">
                <h3>조회 · 앱 표시 미리보기</h3>
                <p>
                  문맥과 적용 위치를 먼저 확인하세요. 임시 저장·승인·게시는
                  수정본 보호와 연결을 마친 뒤 사용할 수 있어요.
                </p>
                <div className="callout">
                  공지: 앱 번들 읽기
                  <br />
                  사람 검수 이력: 연동 필요
                  <br />
                  배치 실행 이력: 연동 필요
                </div>
                <span className="micro muted">
                  조회 시각 {formatDate(d.refreshed_at)}
                </span>
              </div>
            </section>
          </div>
        </>
      )}
    </>
  );
}
function Priority({ row }: { row: TermRow }) {
  return (
    <Link
      href={`/admin/terms?type=occurrence&id=${encodeURIComponent(row.id)}`}
      className="priority-row"
    >
      <span className="priority-symbol">!</span>
      <div>
        <strong className="serif">{row.term}</strong>
        <p>{row.risk_labels.join(" · ")}</p>
        <span className="micro muted">논문 {row.paper_id}</span>
      </div>
      <Icon name="arrow" size={17} />
    </Link>
  );
}
function EntityQueue<T extends { id: string }>({
  data,
  selected,
  title,
  searchLabel,
  query,
  onSearch,
  onSelect,
  label,
  meta,
}: {
  data: PageResult<T> & Envelope;
  selected: string | null;
  title: string;
  searchLabel: string;
  query: string;
  onSearch: (q: string) => void;
  onSelect: (id: string) => void;
  label: (row: T) => string;
  meta: (row: T) => string;
}) {
  const { params, change } = useQuery();
  return (
    <aside className="panel queue-panel">
      <div className="panel-heading">
        <h2>{title}</h2>
        <Badge>{data.total}</Badge>
      </div>
      <div className="queue-controls">
        <SearchBox label={searchLabel} query={query} onSearch={onSearch} />
      </div>
      <ScrollList>
        {data.rows.length ? (
          data.rows.map((row) => (
            <button
              key={row.id}
              className={`queue-row ${row.id === selected ? "selected" : ""}`}
              aria-pressed={row.id === selected}
              onClick={() => onSelect(row.id)}
            >
              <strong>{label(row)}</strong>
              <span className="micro muted">{meta(row)}</span>
            </button>
          ))
        ) : (
          <StatePanel empty="검색 결과가 없어요" />
        )}
      </ScrollList>
      <footer className="queue-footer">
        목록과 상세를 함께 확인해요.
        {data.next_cursor && (
          <button
            className="text-button"
            onClick={() =>
              change({ cursor: data.next_cursor, id: null, sentence: null })
            }
          >
            다음 페이지 →
          </button>
        )}
        {params.has("cursor") && (
          <button
            className="text-button"
            onClick={() => change({ cursor: null, id: null, sentence: null })}
          >
            첫 페이지로
          </button>
        )}
      </footer>
    </aside>
  );
}
export function PaperScreen() {
  const { params, change } = useQuery();
  const list = useResource<PageResult<Paper> & Envelope>(
    `/api/admin/v1/papers?${listQuery(params.toString())}`,
  );
  const selected = params.get("id") ?? list.data?.rows[0]?.id ?? null;
  const detail = useResource<Detail<Paper>>(
    selected ? `/api/admin/v1/papers/${encodeURIComponent(selected)}` : null,
  );
  return (
    <>
      <PageIntro
        eyebrow="PAPER REVIEW"
        title="논문 검수"
        description="초록을 근거로 요약·번역·용어 적용을 확인하세요."
      />
      <div className="content-workbench">
        {list.data ? (
          <EntityQueue
            data={list.data}
            selected={selected}
            title="논문 목록"
            searchLabel="논문 검색"
            query={params.get("query") ?? ""}
            onSearch={(query) => change({ query, id: null })}
            onSelect={(id) => change({ id, sentence: null })}
            label={(p) => p.title_ko ?? p.title_en}
            meta={(p) =>
              `${p.id} · ${p.status === "ready" ? "AI 처리 완료" : p.status === "failed" ? "AI 처리 실패" : "AI 처리 대기"}`
            }
          />
        ) : (
          <section className="panel">
            <StatePanel
              loading={list.loading}
              error={list.error}
              retry={list.retry}
            />
          </section>
        )}
        {detail.data ? (
          <PaperEditor
            key={selected}
            detail={detail.data}
            sentenceId={params.get("sentence")}
            onSentence={(sentence) => change({ sentence })}
          />
        ) : (
          <section className="panel span-two">
            <StatePanel
              loading={detail.loading}
              error={detail.error}
              retry={detail.retry}
              empty="논문을 선택해 주세요"
            />
          </section>
        )}
      </div>
    </>
  );
}
function PaperEditor({
  detail,
  sentenceId,
  onSentence,
}: {
  detail: Detail<Paper>;
  sentenceId: string | null;
  onSentence: (id: string) => void;
}) {
  const p = detail.value;
  const [tab, setTab] = useState("summary");
  const sentence =
    p.sentences.find((s) => s.id === sentenceId) ?? p.sentences[0];
  useEffect(() => {
    if (!sentence?.id) return;
    document
      .getElementById(`original-${p.id}-${sentence.id}`)
      ?.scrollIntoView({ block: "nearest" });
    if (tab === "translation")
      document
        .getElementById(`translation-${p.id}-${sentence.id}`)
        ?.scrollIntoView({ block: "nearest" });
  }, [sentence?.id, p.id, tab]);
  const preview = projectPaperForPreview({
    paper: p,
    senses: detail.all_senses ?? [],
    showAiReviewedTerms: detail.show_ai_reviewed_terms ?? false,
  });
  return (
    <>
      <section className="panel editor-panel">
        <header className="entity-header">
          <div className="micro muted">논문 {p.id}</div>
          <h2 className="content-title">{p.title_ko ?? p.title_en}</h2>
          <p className="serif muted">{p.title_en}</p>
          <div className="inline">
            <Status status={p.status} />
            <Badge>사람 검수 연동 전</Badge>
          </div>
          <div className="underline-tabs">
            {[
              ["summary", "요약 · 근거"],
              ["translation", "문장별 번역"],
              ["terms", "용어 적용"],
            ].map(([key, label]) => (
              <button
                key={key}
                aria-pressed={tab === key}
                onClick={() => setTab(key)}
                className={tab === key ? "active" : ""}
              >
                {label}
              </button>
            ))}
          </div>
        </header>
        <div className="editor-scroll">
          <section className="editor-section">
            {tab === "summary" ? (
              <>
                <label className="field">
                  한국어 제목
                  <input readOnly value={p.title_ko ?? ""} />
                </label>
                <label className="field">
                  AI 요약
                  <textarea
                    rows={5}
                    readOnly
                    value={p.summary_ko ?? ""}
                    placeholder="요약이 아직 없어요"
                  />
                </label>
                <h3>핵심 내용 · 근거 연결</h3>
                {p.key_points.length ? (
                  p.key_points.map((k) => (
                    <div key={k.idx} className="evidence-card">
                      <p>{k.claim_ko}</p>
                      <div className="inline">
                        {k.evidence_sentence_ids.map((id) => (
                          <button
                            key={id}
                            className={`sentence-link ${sentence?.id === id ? "active" : ""}`}
                            onClick={() => {
                              setTab("translation");
                              onSentence(id);
                            }}
                          >
                            근거 {id} ↗
                          </button>
                        ))}
                      </div>
                    </div>
                  ))
                ) : (
                  <div className="callout">
                    근거가 연결된 핵심 내용이 없어요.
                  </div>
                )}
              </>
            ) : tab === "translation" ? (
              <>
                <h3>문장별 번역</h3>
                {p.sentences
                  .filter((s) => s.kind === "text")
                  .map((s) => (
                    <div
                      id={`translation-${p.id}-${s.id}`}
                      className={`sentence-card ${sentence?.id === s.id ? "focused" : ""}`}
                      key={s.id}
                    >
                      <button
                        className="sentence-link"
                        onClick={() => onSentence(s.id)}
                      >
                        {s.id} 원문 확인 ↗
                      </button>
                      <p className="serif original">{latexDisplay(s.text)}</p>
                      <label className="field">
                        {s.id} 번역
                        <textarea
                          readOnly
                          rows={2}
                          value={s.translation ?? ""}
                        />
                      </label>
                    </div>
                  ))}
              </>
            ) : (
              <>
                <h3>이 논문의 용어</h3>
                {p.glossary.map((g) => (
                  <Link
                    key={g.idx}
                    className="linked-paper"
                    href={`/admin/terms?type=occurrence&id=${encodeURIComponent(JSON.stringify({ paper_id: p.id, idx: g.idx }))}`}
                  >
                    <strong className="serif">{g.term}</strong>
                    <span>
                      {g.ko_span ?? "적용 위치 미확인"} ·{" "}
                      {g.sentence_ids.join(", ")}
                    </span>
                    <small>용어 워크벤치에서 확인 →</small>
                  </Link>
                ))}
              </>
            )}
          </section>
        </div>
        <ReadOnlyActions specific="논문 검수 승인" />
      </section>
      <aside className="context-column">
        <section className="panel">
          <div className="panel-heading">
            <h2>초록 원문</h2>
            <Badge>{sentence?.id ?? "원문"}</Badge>
          </div>
          <div className="preview-body original-text">
            {p.sentences.length ? (
              p.sentences.map((s) => (
                <button
                  key={s.id}
                  id={`original-${p.id}-${s.id}`}
                  className={`original-sentence ${sentence?.id === s.id ? "focused" : ""}`}
                  onClick={() => onSentence(s.id)}
                >
                  <span className="micro muted">{s.id}</span>
                  <p className="serif">
                    <HighlightText
                      text={latexDisplay(s.text)}
                      highlights={preview.en[s.id]}
                    />
                  </p>
                </button>
              ))
            ) : (
              <p className="serif">
                {p.abstract_en || "초록 처리 대기 중이에요."}
              </p>
            )}
          </div>
        </section>
        <section className="panel check-panel">
          <div className="panel-heading">
            <h2>현재 노출 · 생성 정보</h2>
          </div>
          <div>
            <p>
              <span>날짜별 목록 노출</span>
              <strong>
                {p.exposures.some((x) => x.is_exposed) ? "노출됨" : "미노출"}
              </strong>
            </p>
            <p>
              <span>원출처 철회</span>
              <strong>{p.withdrawn ? "철회됨" : "아니요"}</strong>
            </p>
            <p>
              <span>사람 검수</span>
              <strong>연동 필요</strong>
            </p>
            <p>
              <span>생성 시각</span>
              <strong>{formatDate(p.generated_at)}</strong>
            </p>
          </div>
        </section>
        <p className="micro muted">
          AI 처리 완료는 사람의 검수 승인을 뜻하지 않아요. 현재 앱의 공개 정책은
          유지해요.
        </p>
      </aside>
    </>
  );
}
export function NewsScreen() {
  const { params, change } = useQuery();
  const tab = params.get("tab") === "model" ? "models" : "news";
  const list = useResource<
    PageResult<News | Model> &
      Envelope & { source_options?: { id: string; label: string }[] }
  >(`/api/admin/v1/${tab}?${listQuery(params.toString())}`);
  const selected = params.get("id") ?? list.data?.rows[0]?.id ?? null;
  const detail = useResource<Detail<News | Model>>(
    selected ? `/api/admin/v1/${tab}/${encodeURIComponent(selected)}` : null,
  );
  return (
    <>
      <PageIntro
        eyebrow="OFFICIAL NEWS & MODELS"
        title="공식 AI 소식 검수"
        description="출처와 근거를 확인하고, 유형에 맞게 콘텐츠를 검토하세요."
      />
      <div className="page-toolbar">
        <div className="segmented">
          <button
            className={tab === "news" ? "active" : ""}
            onClick={() =>
              change({
                tab: "news",
                id: null,
                source: null,
                query: null,
                kind: null,
              })
            }
          >
            공식 소식
          </button>
          <button
            className={tab === "models" ? "active" : ""}
            onClick={() =>
              change({
                tab: "model",
                id: null,
                source: null,
                query: null,
                kind: null,
              })
            }
          >
            모델 정보
          </button>
        </div>
        {tab === "news" && (
          <label className="filter-select">
            출처
            <select
              value={params.get("source") ?? ""}
              onChange={(e) => change({ source: e.target.value, id: null })}
            >
              <option value="">전체 출처</option>
              {list.data?.source_options?.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.label}
                </option>
              ))}
            </select>
          </label>
        )}
        {tab === "news" && (
          <label className="filter-select">
            유형
            <select
              value={params.get("kind") ?? ""}
              onChange={(e) => change({ kind: e.target.value, id: null })}
            >
              <option value="">전체</option>
              <option value="post">공식 발표</option>
              <option value="notice">공지</option>
              <option value="release">릴리스</option>
            </select>
          </label>
        )}
      </div>
      <div className="content-workbench">
        {list.data ? (
          <EntityQueue
            data={list.data}
            selected={selected}
            title={tab === "news" ? "소식 목록" : "모델 목록"}
            searchLabel="소식 검색"
            query={params.get("query") ?? ""}
            onSearch={(query) => change({ query, id: null })}
            onSelect={(id) => change({ id })}
            label={(n) =>
              "title_en" in n ? (n.title_ko ?? n.title_en) : n.name
            }
            meta={(n) =>
              "source_label" in n
                ? n.source_label
                : `${n.author} · 순위 ${n.rank}`
            }
          />
        ) : (
          <section className="panel">
            <StatePanel
              loading={list.loading}
              error={list.error}
              retry={list.retry}
            />
          </section>
        )}
        {detail.data ? (
          "title_en" in detail.data.value ? (
            <NewsEditor
              n={detail.data.value}
              onRelated={(id) =>
                change({ id, query: null, source: null, kind: null })
              }
            />
          ) : (
            <ModelEditor model={detail.data.value} />
          )
        ) : (
          <section className="panel span-two">
            <StatePanel
              loading={detail.loading}
              error={detail.error}
              retry={detail.retry}
              empty="소식을 선택해 주세요"
            />
          </section>
        )}
      </div>
    </>
  );
}
function NewsEditor({
  n,
  onRelated,
}: {
  n: News;
  onRelated: (id: string) => void;
}) {
  return (
    <>
      <section className="panel editor-panel">
        <header className="entity-header">
          <div className="inline micro muted">
            {n.source_label} · {formatDate(n.published_at)}
          </div>
          <h2 className="content-title">{n.title_ko ?? n.title_en}</h2>
          <div className="inline">
            <Status status={n.kind} />
            {n.thin && <Badge>원문 소개문</Badge>}
            <Badge>사람 검수 연동 전</Badge>
          </div>
        </header>
        <div className="editor-scroll">
          <section className="editor-section">
            <label className="field">
              한국어 제목
              <input readOnly value={n.title_ko ?? ""} />
            </label>
            <label className="field">
              {n.thin ? "원문 소개문 번역" : "한국어 요약"}
              <textarea
                readOnly
                rows={4}
                value={n.summary_ko ?? ""}
                placeholder={
                  n.kind === "release"
                    ? "릴리스는 요약 없이 핵심 변경만 제공할 수 있어요."
                    : "요약이 없어요"
                }
              />
            </label>
            <h3>핵심 내용 · 수집 근거</h3>
            {n.key_points.length ? (
              n.key_points.map((k, i) => (
                <div className="evidence-card" key={i}>
                  <p>{k.text}</p>
                  {k.quote ? (
                    <blockquote>{k.quote}</blockquote>
                  ) : (
                    <p className="micro muted">
                      별도 근거 인용이 없는 변경 항목이에요.
                    </p>
                  )}
                  {k.para != null && <Badge>원문 문단 {k.para}</Badge>}
                </div>
              ))
            ) : (
              <div className="callout">
                수집된 핵심 내용이 없어요. 소개문만 있는 소식에 내용을 추측해
                추가하지 않아요.
              </div>
            )}
            <h3>관련 소식</h3>
            {n.related.length ? (
              n.related.map((id) => (
                <button
                  className="linked-paper"
                  key={id}
                  onClick={() => onRelated(id)}
                >
                  <span>{id}</span>
                  <span>관련 소식 확인 →</span>
                </button>
              ))
            ) : (
              <p className="muted">연결된 관련 소식이 없어요.</p>
            )}
          </section>
        </div>
        <ReadOnlyActions specific="소식 검수 승인" />
      </section>
      <aside className="context-column">
        <section className="panel">
          <div className="panel-heading">
            <h2>원문 · 출처</h2>
          </div>
          <div className="preview-body">
            <p className="serif original">{n.title_en}</p>
            <ExternalLink url={n.url}>원문에서 근거 확인</ExternalLink>
            <p className="micro muted">
              원문 전문은 저장되어 있지 않아요. 수집된 근거와 원문 링크로 확인해
              주세요.
            </p>
            <div className="info-row">
              <span>출처</span>
              <strong>{n.source_label}</strong>
            </div>
            <div className="info-row">
              <span>발행</span>
              <strong>{formatDate(n.published_at)}</strong>
            </div>
            <div className="info-row">
              <span>수집</span>
              <strong>{formatDate(n.collected_at)}</strong>
            </div>
          </div>
        </section>
        <div className="callout micro">
          사람 검수와 현재 앱 공개 여부는 별개예요. 검수 승인으로 공개 정책을
          바꾸지 않아요.
        </div>
      </aside>
    </>
  );
}
function ModelEditor({ model: m }: { model: Model }) {
  return (
    <>
      <section className="panel editor-panel">
        <header className="entity-header">
          <div className="micro muted">
            {m.author} · 트렌딩 {m.rank}위
          </div>
          <h2 className="serif entity-title">{m.name}</h2>
          <Badge>제작사 카드 검토</Badge>
        </header>
        <div className="editor-scroll">
          <section className="editor-section">
            {m.card ? (
              <>
                <h3>제작사가 밝힌 강점</h3>
                {m.card.strengths.map((s, i) => (
                  <div className="evidence-card" key={i}>
                    {s}
                  </div>
                ))}
                <h3>제작사 벤치마크</h3>
                <p className="micro muted">
                  제작사 측정값이에요. 지표·단위가 다른 점수는 직접 비교하지
                  않아요.
                </p>
                {m.card.benchmarks.map((b, i) => (
                  <div className="info-row" key={i}>
                    <span>{b.name}</span>
                    <strong>{b.score}</strong>
                  </div>
                ))}
                <label className="field">
                  제약 사항
                  <textarea readOnly rows={3} value={m.card.limitation ?? ""} />
                </label>
              </>
            ) : (
              <StatePanel empty="제작사 카드 정보가 없어요" />
            )}
          </section>
        </div>
        <ReadOnlyActions specific="모델 검수 승인" />
      </section>
      <aside className="context-column">
        <section className="panel">
          <div className="panel-heading">
            <h2>모델 메타데이터</h2>
          </div>
          <div className="preview-body">
            <ExternalLink url={m.url}>원본 모델 카드</ExternalLink>
            {[
              ["ID", m.id],
              ["과제", m.task ?? "정보 없음"],
              ["파라미터", m.params?.toLocaleString() ?? "정보 없음"],
              ["라이선스", m.license ?? "정보 없음"],
              ["수집", formatDate(m.collected_at)],
            ].map(([k, v]) => (
              <div className="info-row" key={k}>
                <span>{k}</span>
                <strong>{v}</strong>
              </div>
            ))}
          </div>
        </section>
        <p className="micro muted">
          순위·다운로드 등 관측 수치는 편집 대상이 아니에요.
        </p>
      </aside>
    </>
  );
}
export function NoticesScreen() {
  const { params, change } = useQuery();
  const list = useResource<PageResult<Notice> & Envelope>(
    `/api/admin/v1/notices?${listQuery(params.toString())}`,
  );
  const selected = params.get("id") ?? list.data?.rows[0]?.id ?? null;
  const detail = useResource<Detail<Notice>>(
    selected ? `/api/admin/v1/notices/${encodeURIComponent(selected)}` : null,
  );
  return (
    <>
      <PageIntro
        eyebrow="ANNOUNCEMENTS"
        title="공지사항 관리"
        description="현재 앱에 포함된 공지를 확인하고, 원격 게시 연결 범위를 살펴보세요."
      >
        <button className="button primary" disabled>
          새 공지 작성
        </button>
      </PageIntro>
      <div className="callout notice-connection">
        <Badge>앱 연동 전</Badge>
        <span>
          현재 앱은 번들 Markdown을 읽어요. 웹에서 게시해도 새 앱 연결 전에는
          전달되지 않아요.
        </span>
      </div>
      <div className="content-workbench">
        {list.data ? (
          <EntityQueue
            data={list.data}
            selected={selected}
            title="앱 번들 공지"
            searchLabel="공지 검색"
            query={params.get("query") ?? ""}
            onSearch={(query) => change({ query, id: null })}
            onSelect={(id) => change({ id })}
            label={(n) => n.title}
            meta={(n) => `${n.date} · 앱 포함본`}
          />
        ) : (
          <section className="panel">
            <StatePanel
              loading={list.loading}
              error={list.error}
              retry={list.retry}
            />
          </section>
        )}
        {detail.data ? (
          <>
            <section className="panel editor-panel">
              <header className="entity-header">
                <div className="micro muted">
                  저장소 번들 snapshot · b8e5c6a
                </div>
                <h2 className="content-title">{detail.data.value.title}</h2>
                <Badge>앱 번들 · 원격 게시 아님</Badge>
              </header>
              <div className="editor-scroll">
                <section className="editor-section">
                  <label className="field">
                    제목
                    <input readOnly value={detail.data.value.title} />
                  </label>
                  <label className="field">
                    표시 날짜
                    <input readOnly value={detail.data.value.date} />
                  </label>
                  <label className="field">
                    Markdown 본문
                    <textarea
                      className="markdown-source"
                      readOnly
                      rows={16}
                      value={detail.data.value.body}
                    />
                  </label>
                </section>
              </div>
              <ReadOnlyActions specific="공지 게시" />
            </section>
            <aside className="context-column">
              <section className="panel">
                <div className="panel-heading">
                  <h2>본문 미리보기</h2>
                </div>
                <div className="preview-body markdown-preview">
                  <h3>{detail.data.value.title}</h3>
                  <span className="micro muted">{detail.data.value.date}</span>
                  {detail.data.value.body.split("\n\n").map((block, i) => (
                    <p key={i}>{block}</p>
                  ))}
                </div>
              </section>
              <p className="micro muted">
                조회용 텍스트 미리보기예요. 새 공지 작성·초안·공개 버전 관리는
                R3에서 연결해요.
              </p>
            </aside>
          </>
        ) : (
          <section className="panel span-two">
            <StatePanel
              loading={detail.loading}
              error={detail.error}
              retry={detail.retry}
            />
          </section>
        )}
      </div>
    </>
  );
}
type Operations = Envelope & {
  state: string;
  rows: unknown[];
  label: string;
  scheduled_at: string;
  digests: { date: string; status: string; last_success_at: string | null }[];
};
export function OperationsScreen() {
  const sources = useResource<
    Envelope & {
      rows: Source[];
      blocked_urls: string[];
      catalog_baseline: string;
    }
  >("/api/admin/v1/sources");
  const runs = useResource<Operations>("/api/admin/v1/operations/runs");
  return (
    <>
      <PageIntro
        eyebrow="SOURCES & OPERATIONS"
        title="출처 · 운영 상태"
        description="수집 출처와 관측 가능한 상태를 확인해요. 실행 결과는 계측과 구분해 표시해요."
      />
      <div className="overview-grid operations-overview">
        <div className="metric-card">
          <span>예약된 배치</span>
          <strong className="time">
            02:17 <small>KST</small>
          </strong>
          <p>실제 실행 시작·종료 시각과 달라요.</p>
        </div>
        <div className="metric-card">
          <span>마지막 전체 실행</span>
          <strong className="text-metric">연동 필요</strong>
          <p>수집 시각으로 대신 표시하지 않아요.</p>
        </div>
        <div className="metric-card">
          <span>출처별 실행 결과</span>
          <strong className="text-metric">계측 연결 전</strong>
          <p>성공·일부 실패·실패를 구분할 예정이에요.</p>
        </div>
      </div>
      <div className="operations-grid">
        <section className="panel source-table">
          <div className="panel-heading">
            <h2>공식 수집 출처</h2>
            <Badge>코드 기준 · {sources.data?.catalog_baseline ?? "—"}</Badge>
          </div>
          {sources.data ? (
            <table>
              <thead>
                <tr>
                  <th>출처</th>
                  <th>수집 방식</th>
                  <th>권리 검토 기록</th>
                  <th>참조</th>
                </tr>
              </thead>
              <tbody>
                {sources.data.rows.map((s) => (
                  <tr key={s.id}>
                    <td>
                      <strong>{s.label}</strong>
                      <small>{s.id}</small>
                    </td>
                    <td>{s.method}</td>
                    <td>
                      <Badge>관리 기록 연동 전</Badge>
                    </td>
                    <td>
                      <ExternalLink url={s.url}>출처</ExternalLink>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <StatePanel
              loading={sources.loading}
              error={sources.error}
              retry={sources.retry}
            />
          )}
          <footer className="queue-footer">
            수집 URL은 현재 Python 코드 정의를 따라요. 새 출처 추가는 이번
            범위에 포함하지 않아요.
          </footer>
        </section>
        <aside className="context-column">
          <section className="panel">
            <div className="panel-heading">
              <h2>실행 이력</h2>
              <Badge>연동 필요</Badge>
            </div>
            <StatePanel
              loading={runs.loading}
              error={runs.error}
              empty="실행 이력 연동 필요"
              retry={runs.error ? runs.retry : undefined}
            />
          </section>
          <section className="panel">
            <div className="panel-heading">
              <h2>재수집 차단 URL</h2>
            </div>
            <div className="preview-body">
              {sources.data ? (
                sources.data.blocked_urls.length ? (
                  <ul className="url-list">
                    {sources.data.blocked_urls.map((url) => (
                      <li key={url}>{url}</li>
                    ))}
                  </ul>
                ) : (
                  <p>등록된 차단 URL이 없어요.</p>
                )
              ) : (
                <p>조회 중이에요.</p>
              )}
              <button className="button secondary" disabled>
                차단 URL 추가
              </button>
              <p className="micro muted">
                차단은 앞으로의 재수집에 적용돼요. 이미 저장된 소식을 자동
                삭제하지 않아요.
              </p>
            </div>
          </section>
        </aside>
      </div>
    </>
  );
}
