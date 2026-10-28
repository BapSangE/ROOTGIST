"use client";
import { useState } from "react";
import { listQuery } from "@/lib/domain/query";
import type {
  TermRow,
  TermDetail,
  PageResult,
  Envelope,
} from "@/lib/domain/contracts";
import {
  projectPaperForPreview,
  latexDisplay,
  normalizeTerm,
} from "@/lib/domain/display";
import {
  Badge,
  Status,
  SearchBox,
  StatePanel,
  ReadOnlyActions,
  HighlightText,
  PageIntro,
  Icon,
  useResource,
  useQuery,
  ScrollList,
} from "./shared";
type TermList = PageResult<TermRow> & Envelope;
export function TermsWorkbench() {
  const { params, change } = useQuery();
  const type = params.get("type") ?? "occurrence";
  const listParams = new URLSearchParams(listQuery(params.toString()));
  if (!listParams.has("type")) listParams.set("type", "occurrence");
  const list = useResource<TermList>(`/api/admin/v1/terms?${listParams}`);
  const selected =
    list.data?.rows.find((r) => r.id === params.get("id")) ??
    (params.has("id") ? undefined : list.data?.rows[0]);
  const requestedId = params.get("id") ?? selected?.id;
  const requestedType =
    selected && selected.id === requestedId
      ? selected.type
      : type === "all"
        ? "sense"
        : type;
  const detail = useResource<TermDetail>(
    requestedId
      ? `/api/admin/v1/terms/${requestedType}/${encodeURIComponent(requestedId)}`
      : null,
  );
  const [hideContext, setHideContext] = useState(false);
  function next() {
    const rows = list.data?.rows ?? [];
    const index = rows.findIndex((r) => r.id === selected?.id);
    if (index >= 0 && index < rows.length - 1)
      change({ id: rows[index + 1].id, paper: null, sentence: null });
    else if (list.data?.next_cursor)
      change({
        cursor: list.data.next_cursor,
        id: null,
        paper: null,
        sentence: null,
      });
  }
  return (
    <>
      <PageIntro
        eyebrow="TERMINOLOGY REVIEW"
        title="용어 검수 워크벤치"
        description="사전 의미와 번역문 속 적용 위치를 한곳에서 확인해요."
      >
        <button
          className="text-button context-toggle"
          onClick={() => setHideContext((v) => !v)}
        >
          {hideContext ? "문맥 펼치기" : "문맥 접기"}
        </button>
        <span className="muted micro">
          {list.data ? `${list.data.total}개 항목` : ""}
        </span>
        <button
          className="button secondary"
          onClick={next}
          disabled={
            !selected ||
            (list.data?.rows.at(-1)?.id === selected.id &&
              !list.data?.next_cursor)
          }
        >
          다음 항목 <Icon name="arrow" size={16} />
        </button>
      </PageIntro>
      <div className={`term-workbench ${hideContext ? "context-hidden" : ""}`}>
        <aside className="panel queue-panel">
          <div className="panel-heading">
            <h2>검토 목록</h2>
            <Badge>{list.data?.total ?? "—"}</Badge>
          </div>
          <div className="queue-controls">
            <SearchBox
              label="용어 검색"
              query={params.get("query") ?? ""}
              onSearch={(query) => change({ query, id: null })}
            />
            <div className="segmented compact" aria-label="검수 유형">
              {[
                ["occurrence", "적용 위치"],
                ["sense", "사전 의미"],
                ["candidate", "후보"],
              ].map(([value, label]) => (
                <button
                  key={value}
                  className={type === value ? "active" : ""}
                  aria-pressed={type === value}
                  onClick={() =>
                    change({
                      type: value,
                      id: null,
                      paper: null,
                      sentence: null,
                    })
                  }
                >
                  {label}
                </button>
              ))}
            </div>
            <label className="filter-select">
              상태
              <select
                value={params.get("filter") ?? "all"}
                onChange={(e) => change({ filter: e.target.value, id: null })}
              >
                <option value="all">전체 상태</option>
                <option value="risks">적용 위험 우선</option>
                <option value="pending">검토 대기</option>
                <option value="approved">의미 승인</option>
                <option value="deferred">수정 필요</option>
              </select>
            </label>
          </div>
          <ScrollList ready={Boolean(list.data)}>
            {list.loading || list.error ? (
              <StatePanel
                loading={list.loading}
                error={list.error}
                retry={list.retry}
              />
            ) : !list.data?.rows.length ? (
              <StatePanel empty="검색 결과가 없어요" />
            ) : (
              list.data.rows.map((row) => (
                <button
                  key={row.id}
                  className={`queue-row ${selected?.id === row.id ? "selected" : ""}`}
                  onClick={() =>
                    change({ id: row.id, paper: null, sentence: null })
                  }
                  aria-pressed={selected?.id === row.id}
                >
                  <span className="serif queue-term">{row.term}</span>
                  <span className="queue-ko">
                    {row.canonical_ko ?? "한국어 표기 미확정"}
                  </span>
                  <span className="micro muted">
                    {row.risk_labels[0] ??
                      (row.type === "candidate"
                        ? "후보 · AI 제안"
                        : "의미 · 검토 대상")}
                    {row.risk_count > 1 ? ` 외 ${row.risk_count - 1}건` : ""}
                  </span>
                </button>
              ))
            )}
          </ScrollList>
          <footer className="queue-footer">
            적용 위험 우선 · 관측 수와 논문 수 구분
            {list.data?.next_cursor && (
              <button
                className="text-button"
                onClick={() =>
                  change({ cursor: list.data!.next_cursor, id: null })
                }
              >
                다음 50개 →
              </button>
            )}
            {params.has("cursor") && (
              <button
                className="text-button"
                onClick={() => change({ cursor: null, id: null })}
              >
                첫 페이지로
              </button>
            )}
          </footer>
        </aside>
        {detail.data ? (
          <TermEditor
            key={`${requestedType}:${requestedId}:${params.get("paper") ?? ""}`}
            detail={detail.data}
            paperId={params.get("paper")}
            sentenceId={params.get("sentence")}
            hideContext={hideContext}
            onContext={(paper, sentence) => change({ paper, sentence })}
          />
        ) : (
          <section className="panel span-two">
            <StatePanel
              loading={detail.loading || list.loading}
              error={detail.error}
              retry={detail.retry}
              empty={
                list.data?.rows.length
                  ? "항목을 선택해 주세요"
                  : "검토할 항목이 없어요"
              }
            />
          </section>
        )}
      </div>
    </>
  );
}
function TermEditor({
  detail,
  paperId,
  sentenceId,
  hideContext,
  onContext,
}: {
  detail: TermDetail;
  paperId: string | null;
  sentenceId: string | null;
  hideContext: boolean;
  onContext: (paper: string, sentence: string | null) => void;
}) {
  const {
    row,
    sense,
    candidate,
    papers,
    aliases,
    all_senses,
    show_ai_reviewed_terms,
  } = detail.value;
  const paper = papers.find((p) => p.id === paperId) ?? papers[0];
  const glossary = paper?.glossary.find((g) =>
    row.type === "occurrence"
      ? g.idx === row.idx
      : row.type === "sense"
        ? g.sense_id === row.sense_id
        : normalizeTerm(g.term) === row.id,
  );
  const sentence =
    paper?.sentences.find((s) => s.id === sentenceId) ??
    paper?.sentences.find((s) => glossary?.sentence_ids.includes(s.id)) ??
    paper?.sentences.find((s) => s.kind === "text");
  const [span, setSpan] = useState<string | null>(glossary?.ko_span ?? null);
  const [assumeApproved, setAssumeApproved] = useState(false);
  const [tab, setTab] = useState("meaning");
  const [showDraft, setShowDraft] = useState(true);
  const dirty = span !== (glossary?.ko_span ?? null);
  const projectedPaper =
    paper && glossary
      ? {
          ...paper,
          glossary: paper.glossary.map((g) =>
            g.idx === glossary.idx
              ? { ...g, ko_span: showDraft ? span : glossary.ko_span }
              : g,
          ),
        }
      : paper;
  const preview = projectedPaper
    ? projectPaperForPreview({
        paper: projectedPaper,
        senses: all_senses,
        showAiReviewedTerms: show_ai_reviewed_terms,
        assumeApproved,
      })
    : null;
  const label = (span ?? "").replace(/\s*\(.*\)$/, "");
  const matchCount =
    label && sentence?.translation
      ? sentence.translation.split(label).length - 1
      : 0;
  return (
    <>
      <section className="panel editor-panel">
        <header className="entity-header">
          <div className="micro muted">
            {row.type === "candidate"
              ? "용어 후보"
              : row.type === "occurrence"
                ? "논문별 적용 위치"
                : "사전 의미"}{" "}
            · {sense?.sense_id ?? candidate?.normalized_form ?? row.paper_id}
          </div>
          <h2 className="serif entity-title">{row.term}</h2>
          <div className="inline">
            <Status status={row.status} />
            {sense?.ai_review_status === "first_pass_complete" && (
              <Badge>AI 1차 검토 완료</Badge>
            )}
            {row.risk_count > 0 && <Badge>! 적용 확인 {row.risk_count}</Badge>}
          </div>
          <div className="underline-tabs" aria-label="검수 정보">
            {[
              ["meaning", "의미 · 표기"],
              ["papers", `적용 논문 ${papers.length}`],
              ["note", "검수 메모"],
            ].map(([value, label]) => (
              <button
                key={value}
                aria-pressed={tab === value}
                className={tab === value ? "active" : ""}
                onClick={() => setTab(value)}
              >
                {label}
              </button>
            ))}
          </div>
        </header>
        <div className="editor-scroll">
          {tab === "meaning" ? (
            <>
              <section className="editor-section">
                <div className="section-title">
                  <h3>01&nbsp; 사전 의미</h3>
                  <span className="micro muted">
                    {sense
                      ? "다른 논문에도 영향을 줘요"
                      : "후보 표기 · 사전 반영 전"}
                  </span>
                </div>
                <label className="field">
                  {candidate
                    ? "AI 제안 한국어 표기"
                    : "한국어 표기 · 사전 의미"}
                  <input
                    readOnly
                    value={
                      candidate?.canonical_ko_draft ??
                      sense?.canonical_ko ??
                      row.canonical_ko ??
                      ""
                    }
                  />
                </label>
                <label className="field">
                  {candidate ? "AI 추출 정의" : "일반 정의 · 사전 의미"}
                  <textarea
                    readOnly
                    rows={3}
                    value={
                      sense?.definition_ko ??
                      candidate?.definition_ko ??
                      row.definition
                    }
                  />
                </label>
                {candidate && (
                  <div className="inline micro">
                    <Badge>관측 수 {candidate.seen_count}</Badge>
                    <span>연결 논문 {row.paper_count}편</span>
                  </div>
                )}
                <div className="field-label">영문 별칭</div>
                <div className="inline">
                  {aliases.length ? (
                    aliases.map((a) => (
                      <Badge key={a.alias_id}>
                        {a.surface_form} ·{" "}
                        {a.review_status === "approved" ? "승인" : "대기"}
                      </Badge>
                    ))
                  ) : (
                    <span className="muted micro">등록된 별칭이 없어요</span>
                  )}
                </div>
                <p className="micro muted">
                  별칭 추가·중복 후보 연결은 저장 경로 검증 후 제공해요.
                </p>
                {sense && (
                  <div className="callout micro">
                    현재 워커의 자동 연결 허용 규칙은 별도 통합이 필요해요.
                    스위치만으로 운영 규칙을 바꾸지 않아요.
                  </div>
                )}
              </section>
              <section className="editor-section">
                <div className="section-title">
                  <h3>02&nbsp; 이 논문의 적용 위치</h3>
                  <Badge>논문 1편 범위</Badge>
                </div>
                {paper && sentence ? (
                  <>
                    <label className="field context-selector">
                      연결 논문
                      <select
                        value={paper.id}
                        onChange={(e) => onContext(e.target.value, null)}
                      >
                        {papers.map((p) => (
                          <option key={p.id} value={p.id}>
                            {p.title_ko ?? p.title_en}
                          </option>
                        ))}
                      </select>
                    </label>
                    <div className="sentence-card">
                      <div className="inline micro muted">
                        <span>
                          {detail.fixture ? "가상 논문" : "논문"} {paper.id}
                        </span>
                        <label>
                          문장{" "}
                          <select
                            aria-label="적용 문장"
                            value={sentence.id}
                            onChange={(e) =>
                              onContext(paper.id, e.target.value)
                            }
                          >
                            {paper.sentences
                              .filter((s) => s.kind === "text")
                              .map((s) => (
                                <option key={s.id}>{s.id}</option>
                              ))}
                          </select>
                        </label>
                      </div>
                      <p className="serif original">
                        {latexDisplay(sentence.text)}
                      </p>
                      <p>{sentence.translation ?? "번역이 아직 없어요"}</p>
                    </div>
                    <label className="field">
                      번역문에서 강조할 표기
                      <input
                        value={span ?? ""}
                        onChange={(e) => setSpan(e.target.value)}
                        placeholder="번역문에서 실제 사용된 표기"
                        disabled={!glossary}
                      />
                    </label>
                    <div className="inline micro">
                      <span>
                        {matchCount
                          ? `✓ ${sentence.id} 번역문에서 ${matchCount}회 일치`
                          : "! 번역문에서 일치하는 표기를 찾지 못했어요"}
                      </span>
                      <span className="muted">
                        앱 강조{" "}
                        {preview?.ko[sentence.id]?.filter(
                          (h) => h.idx === glossary?.idx,
                        ).length ?? 0}
                        회
                      </span>
                    </div>
                    <p className="micro muted">
                      부분 문자열 미리보기예요. 특정 두 번째 등장만 지정할 수는
                      없어요.
                    </p>
                    <div className="inline">
                      <Badge>
                        {span === null
                          ? "위치 미확인 · null"
                          : span === ""
                            ? "표기 없음 확인 · 빈 문자열"
                            : "입력한 부분 문자열"}
                      </Badge>
                      {glossary && (
                        <Badge>
                          영문 강조 {glossary.highlight ? "허용" : "해제"}
                        </Badge>
                      )}
                    </div>
                    {dirty && (
                      <p className="micro draft-note" role="status">
                        입력값으로 미리보는 중 · 저장되지 않으며 항목 이동 시
                        초기화돼요.
                      </p>
                    )}
                  </>
                ) : (
                  <div className="callout">
                    연결된 문장 문맥이 없어요. 관측 수만으로 적용 위치를
                    확인했다고 표시하지 않아요.
                  </div>
                )}
              </section>
            </>
          ) : tab === "papers" ? (
            <section className="editor-section">
              <h3>연결된 논문</h3>
              {papers.length ? (
                papers.map((p) => (
                  <button
                    key={p.id}
                    className="linked-paper"
                    onClick={() => {
                      onContext(p.id, null);
                      setTab("meaning");
                    }}
                  >
                    <span className="micro muted">{p.id}</span>
                    <strong>{p.title_ko ?? p.title_en}</strong>
                    <span className="micro">적용 위치 확인 →</span>
                  </button>
                ))
              ) : (
                <p>연결된 논문이 없어요.</p>
              )}
            </section>
          ) : (
            <section className="editor-section">
              <h3>검수 메모</h3>
              <label className="field">
                현재 사전 의미 메모
                <textarea
                  rows={5}
                  readOnly
                  value={sense?.review_note_ko ?? ""}
                  placeholder="등록된 메모가 없어요"
                />
              </label>
              <p className="micro muted">
                메모·초안·변경 이력 저장은 R1에서 연결해요.
              </p>
            </section>
          )}
        </div>
        <ReadOnlyActions />
      </section>
      {!hideContext && (
        <aside className="context-column">
          <section className="panel preview-panel">
            <div className="panel-heading">
              <h2>문맥 · 앱 표시 예상</h2>
              <Badge>{assumeApproved ? "승인 가정" : "현재 앱 규칙"}</Badge>
            </div>
            <div className="preview-controls">
              <div className="segmented compact">
                <button
                  className={!assumeApproved ? "active" : ""}
                  onClick={() => setAssumeApproved(false)}
                >
                  현재 앱
                </button>
                <button
                  className={assumeApproved ? "active" : ""}
                  onClick={() => setAssumeApproved(true)}
                >
                  승인 가정
                </button>
              </div>
              {dirty && (
                <label className="micro">
                  <input
                    type="checkbox"
                    checked={showDraft}
                    onChange={(e) => setShowDraft(e.target.checked)}
                  />{" "}
                  입력값으로 미리보기
                </label>
              )}
            </div>
            {paper && sentence && preview ? (
              <div className="preview-body">
                <div className="micro muted">
                  {paper.id} · {sentence.id}
                </div>
                <p className="micro">{paper.title_ko ?? paper.title_en}</p>
                <div className="app-preview" data-testid="app-preview">
                  <div className="app-chrome">
                    ‹&nbsp; 초록 읽기 <span>함께&nbsp; ·&nbsp; 가</span>
                  </div>
                  <p className="app-ko">
                    <HighlightText
                      text={sentence.translation ?? ""}
                      highlights={preview.ko[sentence.id]}
                    />
                  </p>
                  <p className="serif app-en">
                    <HighlightText
                      text={latexDisplay(sentence.text)}
                      highlights={preview.en[sentence.id]}
                    />
                  </p>
                  <div className="term-definition">
                    <span className="micro muted">용어 해설</span>
                    <div className="serif">{row.term}</div>
                    <small>
                      {preview.terms.find((g) => g.idx === glossary?.idx)
                        ?.term_ko ?? "한국어 표기 표시 대기"}
                    </small>
                    <p>{glossary?.definition_ko ?? row.definition}</p>
                  </div>
                </div>
                <p className="micro muted">
                  승인 여부와 앱 설정에 따라 실제 표시가 달라져요. 금지 원문은
                  승인 가정에서도 제외해요.
                </p>
              </div>
            ) : (
              <StatePanel empty="문맥을 연결하면 앱 예상 표시를 볼 수 있어요" />
            )}
          </section>
          <section className="panel check-panel">
            <div className="panel-heading">
              <h2>적용 전 확인</h2>
            </div>
            <div>
              <p>
                <span>원문 · 번역 연결</span>
                <strong>{sentence?.id ?? "확인 필요"}</strong>
              </p>
              <p>
                <span>번역문 표기 일치</span>
                <strong>{matchCount ? `${matchCount}회` : "확인 필요"}</strong>
              </p>
              <p>
                <span>다른 논문 적용 위치</span>
                <strong>별도 검수</strong>
              </p>
            </div>
          </section>
          <p className="micro context-footnote">
            사전 정의와 앱의 ‘이 논문에서의 뜻’은 별개예요. 의미 승인만으로 모든
            적용 위치가 확인되지는 않아요.
          </p>
        </aside>
      )}
    </>
  );
}
