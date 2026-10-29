"use client";
import { useEffect, useEffectEvent, useRef, useState } from "react";
import type {
  Envelope,
  PageResult,
  TermDetail,
  TermRow,
} from "@/lib/domain/contracts";
import { listQuery } from "@/lib/domain/query";
import { latexDisplay, normalizeTerm } from "@/lib/domain/display";
import { reviewContext } from "@/lib/domain/review-context";
import { logout } from "@/lib/server/login-actions";
import { useAdminFixture } from "./admin-shell";
import { ReviewDialog } from "./term-review-dialog";
import {
  HighlightText,
  Icon,
  SearchBox,
  StatePanel,
  Status,
  useQuery,
  useResource,
  ScrollList,
} from "./shared";

type TermList = PageResult<TermRow> & Envelope;
type Changes = Record<string, string | null>;
export function TermsWorkbench() {
  const fixture = useAdminFixture();
  const { params, change } = useQuery();
  const type = params.get("type") ?? "occurrence";
  const query = new URLSearchParams(listQuery(params.toString()));
  if (!query.has("type")) query.set("type", "occurrence");
  const list = useResource<TermList>(`/api/admin/v1/terms?${query}`);
  const selected =
    list.data?.rows.find((r) => r.id === params.get("id")) ??
    (params.has("id") ? undefined : list.data?.rows[0]);
  const requestedId = params.get("id") ?? selected?.id;
  const requestedType =
    selected?.id === requestedId
      ? selected?.type
      : type === "all"
        ? "sense"
        : type;
  const detail = useResource<TermDetail>(
    requestedId
      ? `/api/admin/v1/terms/${requestedType}/${encodeURIComponent(requestedId)}`
      : null,
  );
  const [drawer, setDrawer] = useState<"queue" | "inspector" | null>(null),
    [help, setHelp] = useState(false),
    [related, setRelated] = useState(false);
  const [intent, setIntent] = useState<Changes | null>(null),
    [drafts, setDrafts] = useState<Record<string, string>>({});
  const [assume, setAssume] = useState(false);
  const [searchReset, setSearchReset] = useState(0);
  function dismissIntent() {
    if (intent) {
      setIntent(null);
      setSearchReset((v) => v + 1);
    }
  }
  const pendingFocus = useRef<"search" | null>(null);
  const base = detail.data
    ? reviewContext(detail.data.value, {
        paperId: params.get("paper"),
        sentenceId: params.get("sentence"),
      })
    : null;
  const draftKey = JSON.stringify([
    requestedType,
    requestedId,
    base?.paper?.id,
    base?.glossary?.idx,
  ]);
  const override = drafts[draftKey];
  const ctx = detail.data
    ? reviewContext(detail.data.value, {
        paperId: params.get("paper"),
        sentenceId: params.get("sentence"),
        span: override,
        assumeApproved: assume,
      })
    : null;
  const dirty = override !== undefined && override !== (base?.span ?? null);
  function navigate(v: Changes) {
    if (dirty) {
      setIntent(v);
      return;
    }
    setAssume(false);
    setDrawer(null);
    change(v);
  }
  const index = list.data?.rows.findIndex((r) => r.id === requestedId) ?? -1;
  const canNext =
    !!selected &&
    (index < (list.data?.rows.length ?? 0) - 1 || !!list.data?.next_cursor);
  function move(delta: number) {
    const rows = list.data?.rows ?? [];
    if (index >= 0 && index + delta >= 0 && index + delta < rows.length)
      navigate({ id: rows[index + delta].id, paper: null, sentence: null });
    else if (delta > 0 && list.data?.next_cursor)
      navigate({
        cursor: list.data.next_cursor,
        id: null,
        paper: null,
        sentence: null,
      });
  }
  const step = useEffectEvent(move);
  useEffect(() => {
    function key(e: KeyboardEvent) {
      if (document.querySelector("dialog[open]")) return;
      const target = e.target as HTMLElement;
      const editing = target.matches(
        "input,textarea,select,[contenteditable=true]",
      );
      if (editing || e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === "/") {
        e.preventDefault();
        if (window.matchMedia("(max-width:1199px)").matches) {
          pendingFocus.current = "search";
          setDrawer("queue");
        } else
          (document.querySelector(".queue input") as HTMLInputElement)?.focus();
      }
      if (e.key.toLowerCase() === "j") {
        e.preventDefault();
        step(1);
      }
      if (e.key.toLowerCase() === "k") {
        e.preventDefault();
        step(-1);
      }
    }
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, []);
  useEffect(() => {
    if (drawer === "queue" && pendingFocus.current) {
      pendingFocus.current = null;
      requestAnimationFrame(() =>
        document
          .querySelector<HTMLDialogElement>("dialog[open]")
          ?.querySelector<HTMLInputElement>("input")
          ?.focus(),
      );
    }
  }, [drawer]);
  const hasDraft = Object.keys(drafts).length > 0;
  useEffect(() => {
    if (!hasDraft) return;
    const warn = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = "";
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [hasDraft]);
  function finishNavigation(discard: boolean) {
    if (!intent) return;
    if (discard)
      setDrafts((prev) => {
        const next = { ...prev };
        delete next[draftKey];
        return next;
      });
    change(intent);
    setIntent(null);
    setAssume(false);
    setDrawer(null);
  }
  const queue = (
    <Queue
      list={list}
      searchReset={searchReset}
      params={params}
      type={type}
      selectedId={requestedId}
      onNavigate={navigate}
    />
  );
  const inspector = detail.data ? (
    <Inspector
      detail={detail.data}
      context={ctx}
      onRelated={() => setRelated(true)}
    />
  ) : (
    <StatePanel
      loading={detail.loading || list.loading}
      error={detail.error}
      empty="항목을 선택해 주세요"
      retry={detail.error ? detail.retry : undefined}
    />
  );
  const row = detail.data?.value.row;
  const footerLabel =
    row?.type === "sense"
      ? "의미 승인"
      : row?.type === "candidate"
        ? "후보 검토 승인"
        : "적용 위치 저장";
  const linkedSentence = !!ctx?.glossary?.sentence_ids.includes(
    ctx.sentence?.id ?? "",
  );
  return (
    <>
      <header className="app-header">
        <a
          href="/admin/terms"
          className="brand"
          aria-label="ROOTGIST 용어 검수"
        >
          ROOTGIST
          <span className="divider" />
          <span className="brand-sub">용어 검수</span>
        </a>
        <span className="prototype">
          {fixture ? "가상 데이터 · 로컬 검토본" : "실제 데이터 · 조회 전용"}
        </span>
        <div className="header-actions">
          <button
            className="quiet list-open"
            aria-haspopup="dialog"
            aria-expanded={drawer === "queue"}
            onClick={() => setDrawer("queue")}
          >
            검토 목록 <span className="count">{list.data?.total ?? "—"}</span>
          </button>
          <button
            className="quiet inspector-open"
            aria-haspopup="dialog"
            aria-expanded={drawer === "inspector"}
            onClick={() => setDrawer("inspector")}
          >
            사전 의미
          </button>
          <button
            className="icon-button"
            aria-label="검수 방법과 단축키"
            onClick={() => setHelp(true)}
          >
            ?
          </button>
          {!fixture && (
            <form action={logout}>
              <button className="quiet logout">로그아웃</button>
            </form>
          )}
        </div>
      </header>
      <div className="workspace">
        <aside className="queue" aria-label="검토 목록">
          {queue}
        </aside>
        <main
          className="review"
          id="content"
          tabIndex={-1}
          aria-label="용어 검수 워크벤치"
        >
          {!detail.data || !ctx ? (
            <div className="focus-loading">
              <h1>용어 검수</h1>
              <StatePanel
                loading={detail.loading || list.loading}
                error={detail.error ?? list.error}
                empty={
                  list.data?.rows.length
                    ? "목록에서 항목을 선택해 주세요"
                    : "검색 결과가 없어요"
                }
                retry={
                  detail.error
                    ? detail.retry
                    : list.error
                      ? list.retry
                      : undefined
                }
              />
            </div>
          ) : (
            <>
              <header className="term-heading">
                <div>
                  <div className="eyebrow">
                    {row?.type === "occurrence"
                      ? "논문별 적용 위치"
                      : row?.type === "candidate"
                        ? "AI 추출 후보 · 사전 반영 전"
                        : "사전 의미 · 여러 논문에 적용"}
                  </div>
                  <h1>
                    {row?.term}
                    <span>{row?.canonical_ko ?? "한국어 표기 미확정"}</span>
                  </h1>
                </div>
                <Status status={row!.status} />
              </header>
              <div className="context-line">
                <label className="context-label">
                  <span className="meta-label">연결 논문</span>
                  <select
                    aria-label="연결 논문"
                    disabled={!detail.data.value.papers.length}
                    value={ctx.paper?.id ?? ""}
                    onChange={(e) =>
                      navigate({ paper: e.target.value, sentence: null })
                    }
                  >
                    {detail.data.value.papers.length ? (
                      detail.data.value.papers.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.title_ko ?? p.title_en}
                        </option>
                      ))
                    ) : (
                      <option value="">연결된 논문 없음</option>
                    )}
                  </select>
                </label>
                <span className="paper-id">{ctx.paper?.id}</span>
              </div>
              <div className="sentence-navigation">
                <label className="sentence-select">
                  <span className="meta-label">문장 탐색</span>
                  <select
                    aria-label="적용 문장"
                    disabled={!ctx.texts.length}
                    value={ctx.sentence?.id ?? ""}
                    onChange={(e) => change({ sentence: e.target.value })}
                  >
                    {ctx.texts.map((s) => (
                      <option key={s.id} value={s.id}>
                        {s.id}
                        {ctx.glossary?.sentence_ids.includes(s.id)
                          ? " · 연결"
                          : ""}
                      </option>
                    ))}
                  </select>
                </label>
                <span className="micro subtle">
                  {linkedSentence ? "연결 문장" : "탐색 문장 · 적용 연결 안 됨"}
                </span>
                <span className="sentence-position micro subtle">
                  검토 표기 찾기 · 앱 표시와 별개
                </span>
              </div>
              <section
                className="comparison"
                aria-label="영문 원문과 한국어 번역 비교"
              >
                <article className="reading-pane">
                  <div className="reading-label">
                    <span>
                      영문 원문{" "}
                      <b className="sentence-id">{ctx.sentence?.id}</b>
                    </span>
                    <span className="language">EN</span>
                  </div>
                  <div
                    className="reading-scroll"
                    tabIndex={0}
                    aria-label="영문 원문 문장"
                  >
                    <p className="english inspection">
                      <HighlightText
                        text={latexDisplay(
                          ctx.sentence?.text ?? "연결된 문장 문맥이 없어요",
                        )}
                        highlights={ctx.inspection.en}
                      />
                    </p>
                  </div>
                </article>
                <article className="reading-pane korean-pane">
                  <div className="reading-label">
                    <span>
                      한국어 번역{" "}
                      <b className="sentence-id">{ctx.sentence?.id}</b>
                    </span>
                    <span className="language">KO</span>
                  </div>
                  <div
                    className="reading-scroll"
                    tabIndex={0}
                    aria-label="한국어 번역 문장"
                  >
                    <p>
                      <HighlightText
                        text={ctx.sentence?.translation ?? "번역이 아직 없어요"}
                        highlights={ctx.inspection.ko}
                      />
                    </p>
                  </div>
                </article>
              </section>
              <section className="span-editor">
                <div className="span-input">
                  <label htmlFor="span">번역문에서 강조할 표기</label>
                  <div className="input-wrap">
                    <input
                      id="span"
                      value={ctx.span ?? ""}
                      disabled={!ctx.glossary}
                      placeholder="미지정 · 사전 한국어 표기 사용"
                      aria-describedby="matchInfo"
                      onChange={(e) => {
                        const value = e.target.value;
                        setDrafts((prev) => {
                          const next = { ...prev };
                          if (value === (base?.span ?? ""))
                            delete next[draftKey];
                          else next[draftKey] = value;
                          return next;
                        });
                      }}
                    />
                    {dirty && (
                      <button
                        className="reset-preview"
                        onClick={() =>
                          setDrafts((prev) => {
                            const next = { ...prev };
                            delete next[draftKey];
                            return next;
                          })
                        }
                      >
                        원래대로
                      </button>
                    )}
                  </div>
                </div>
                <div
                  id="matchInfo"
                  className={`match-result ${!ctx.matchCount ? "invalid" : ""}`}
                  aria-live="polite"
                >
                  <b>
                    {ctx.matchCount
                      ? `${ctx.matchCount}회 일치`
                      : "표기 일치 없음"}
                  </b>
                  <span>선택 문장 앱 강조 {ctx.appliedCount}회</span>
                </div>
              </section>
              <section className="app-preview" aria-label="앱 표시 예상">
                <div className="preview-top">
                  <h2>앱 표시 예상</h2>
                  <div className="preview-switch" aria-label="미리보기 기준">
                    <button
                      aria-pressed={!assume}
                      onClick={() => setAssume(false)}
                    >
                      현재 앱
                    </button>
                    <button
                      aria-pressed={assume}
                      onClick={() => setAssume(true)}
                    >
                      승인 가정
                    </button>
                  </div>
                  <span className="preview-tag">
                    AI 검토 표시{" "}
                    {detail.data.value.show_ai_reviewed_terms ? "ON" : "OFF"}
                  </span>
                </div>
                <div
                  className="preview-scroll"
                  tabIndex={0}
                  data-testid="app-preview"
                >
                  <p>
                    <HighlightText
                      text={
                        ctx.sentence?.translation ??
                        "문맥을 연결하면 앱 예상 표시를 볼 수 있어요"
                      }
                      highlights={ctx.projection?.ko[ctx.sentence?.id ?? ""]}
                    />
                  </p>
                </div>
                <div className="preview-foot">
                  {assume ? "승인 가정 · 실제 검토 상태는 바뀌지 않아요. " : ""}
                  {ctx.matchCount > 1 ? "같은 표기는 첫 일치만 강조해요. " : ""}
                  {!ctx.span ? "빈 표기는 사전 한국어 표기를 사용해요. " : ""}
                  문장 순서·겹침·승인·앱 설정을 함께 반영합니다.
                </div>
              </section>
            </>
          )}
        </main>
        <aside className="inspector" aria-label="사전 의미와 별칭">
          {inspector}
        </aside>
      </div>
      <footer className="action-bar">
        <div className="action-note">
          <span className="dot" />
          <span>
            {dirty
              ? "입력값으로 미리보기 · DB 저장 안 됨"
              : "조회 · 로컬 미리보기"}
          </span>
        </div>
        <div className="actions">
          <button
            className="quiet"
            disabled
            title="수정본 보호와 저장 연결 후 사용할 수 있어요"
          >
            수정 필요
          </button>
          <button className="button secondary" disabled>
            임시 저장
          </button>
          <button
            className="button secondary"
            disabled
            title="저장 경로 연결 전에는 변경할 수 없어요"
          >
            {footerLabel}
          </button>
          <button
            className="button primary"
            onClick={() => move(1)}
            disabled={!canNext}
          >
            다음 항목 <Icon name="arrow" size={16} />
          </button>
        </div>
      </footer>
      <ReviewDialog
        open={drawer === "queue"}
        title="검토 목록"
        side="left"
        onClose={() => setDrawer(null)}
      >
        <aside className="queue">{queue}</aside>
      </ReviewDialog>
      <ReviewDialog
        open={drawer === "inspector"}
        title="사전 의미"
        side="right"
        onClose={() => setDrawer(null)}
      >
        <aside className="inspector">{inspector}</aside>
      </ReviewDialog>
      <ReviewDialog
        open={help}
        title="한 화면에서 검토하기"
        onClose={() => setHelp(false)}
      >
        <div className="dialog-copy">
          <p>
            번역 문맥 → 사전 의미 → 강조 위치 → 앱 표시를 확인하고 다음 항목으로
            이동하세요.
          </p>
          <p>
            <kbd>/</kbd> 검색 · <kbd>J</kbd>/<kbd>K</kbd> 다음/이전. 입력
            중이거나 대화상자가 열려 있으면 이동 단축키를 사용하지 않습니다.
          </p>
          <p>
            회색 밑줄은 검토할 표기의 위치이고, 아래 앱 표시 예상의 노란 강조는
            실제 표시 규칙을 반영합니다. 현재는 조회와 로컬 강조 미리보기만
            가능합니다. 임시 저장·승인·별칭·메모 수정은 아직 연결되지
            않았습니다.
          </p>
          <p>
            사전 의미 승인과 논문별 적용 확인은 별개입니다. ‘승인 가정’은 실제
            승인 상태를 바꾸지 않으며, 표시 제외 정의도 승인 가정에서
            제외됩니다.
          </p>
        </div>
      </ReviewDialog>
      <ReviewDialog
        open={!!intent}
        title="변경한 미리보기가 있어요"
        onClose={dismissIntent}
      >
        <p className="dialog-copy">
          미리보기 입력을 유지하거나 버린 뒤 이동할 수 있어요. 유지한 입력도 이
          탭의 메모리에만 남고 실제 DB에는 저장되지 않습니다.
        </p>
        <div className="dialog-actions">
          <button className="button secondary" onClick={dismissIntent}>
            계속 검토
          </button>
          <button
            className="button secondary"
            onClick={() => finishNavigation(true)}
          >
            버리고 이동
          </button>
          <button
            className="button primary"
            onClick={() => finishNavigation(false)}
          >
            미리보기 유지 후 이동
          </button>
        </div>
      </ReviewDialog>
      <ReviewDialog
        open={related}
        title="표기가 비슷한 의미"
        onClose={() => setRelated(false)}
      >
        <div className="dialog-copy">
          <p>
            표기 기준 참고 후보입니다. 동일한 의미나 중복이라고 자동 판정하지
            않습니다.
          </p>
          {detail.data &&
            detail.data.value.all_senses
              .filter(
                (s) =>
                  s.sense_id !== detail.data?.value.sense?.sense_id &&
                  normalizeTerm(s.canonical_en).includes(
                    normalizeTerm(row?.term ?? "").split(" ")[0],
                  ),
              )
              .slice(0, 5)
              .map((s) => (
                <div className="similar-item" key={s.sense_id}>
                  <b className="english">{s.canonical_en}</b>
                  <p>
                    {s.canonical_ko ?? "한국어 표기 없음"} ·{" "}
                    {s.definition_ko ?? "정의 없음"}
                  </p>
                  <small>{s.sense_id}</small>
                </div>
              ))}
          <p className="micro subtle">
            별칭/중복 연결 변경은 지원하지 않습니다.
          </p>
        </div>
      </ReviewDialog>
    </>
  );
}
function Queue({
  searchReset,
  list,
  params,
  type,
  selectedId,
  onNavigate,
}: {
  searchReset: number;
  list: ReturnType<typeof useResource<TermList>>;
  params: URLSearchParams;
  type: string;
  selectedId?: string;
  onNavigate: (v: Changes) => void;
}) {
  return (
    <>
      <div className="queue-head">
        <div className="section-heading">
          <h2>
            검토 목록 <span className="count">{list.data?.total ?? "—"}</span>
          </h2>
          <span className="subtle micro desktop-meta">상태별 필터</span>
        </div>
        <SearchBox
          key={searchReset}
          label="용어 검색"
          query={params.get("query") ?? ""}
          onSearch={(query) =>
            onNavigate({ query, id: null, paper: null, sentence: null })
          }
        />
        <div className="type-tabs" aria-label="검수 유형">
          {[
            ["occurrence", "적용 위치"],
            ["sense", "사전 의미"],
            ["candidate", "후보"],
          ].map(([value, label]) => (
            <button
              key={value}
              aria-pressed={type === value}
              onClick={() =>
                onNavigate({
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
        <label className="filter">
          <span>상태</span>
          <select
            value={params.get("filter") ?? "all"}
            onChange={(e) =>
              onNavigate({
                filter: e.target.value,
                id: null,
                paper: null,
                sentence: null,
              })
            }
          >
            <option value="all">전체 상태</option>
            <option value="risks">적용 위험 우선</option>
            <option value="pending">검토 대기</option>
            <option value="approved">의미 승인</option>
            <option value="deferred">수정 필요</option>
          </select>
        </label>
      </div>
      <ScrollList ready={!!list.data}>
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
              className="queue-row"
              key={row.id}
              aria-pressed={selectedId === row.id}
              onClick={() =>
                onNavigate({ id: row.id, paper: null, sentence: null })
              }
            >
              <span className="row-title">{row.term}</span>
              <span className="row-ko">
                {row.canonical_ko ?? "한국어 표기 미확정"}
              </span>
              <span className="row-meta">
                {row.risk_count > 0 && <span className="risk-dot" />}
                {row.risk_labels[0] ??
                  (row.type === "candidate"
                    ? "후보 · AI 제안"
                    : "의미 검토 대상")}
                {row.risk_count > 1 ? ` 외 ${row.risk_count - 1}건` : ""}
              </span>
            </button>
          ))
        )}
      </ScrollList>
      <div className="queue-bottom">
        {params.has("cursor") ? (
          <button
            className="text-button"
            onClick={() =>
              onNavigate({
                cursor: null,
                id: null,
                paper: null,
                sentence: null,
              })
            }
          >
            첫 페이지
          </button>
        ) : (
          <span>적용 위치와 사전 의미 구분</span>
        )}
        {list.data?.next_cursor && (
          <button
            className="text-button"
            onClick={() =>
              onNavigate({
                cursor: list.data!.next_cursor,
                id: null,
                paper: null,
                sentence: null,
              })
            }
          >
            다음 50개 →
          </button>
        )}
      </div>
    </>
  );
}
function Inspector({
  detail,
  context,
  onRelated,
}: {
  detail: TermDetail;
  context: ReturnType<typeof reviewContext> | null;
  onRelated: () => void;
}) {
  const { row, sense, candidate, aliases } = detail.value;
  return (
    <>
      <div className="inspector-heading">
        <h2>사전 의미</h2>
        <span className="scope-label">여러 논문에 적용 · 조회</span>
      </div>
      <div className="inspector-scroll">
        <div className="meaning-meta">
          <Status
            status={
              sense?.review_status ?? candidate?.review_status ?? row.status
            }
          />
          <span className="micro subtle" title={sense?.sense_id}>
            {sense?.sense_id ?? "의미 미연결"}
          </span>
        </div>
        <label className="field">
          {candidate ? "AI 제안 한국어 표기" : "한국어 표기"}
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
        <label className="field definition-field">
          일반 정의
          <textarea
            readOnly
            rows={4}
            value={
              sense?.definition_ko ?? candidate?.definition_ko ?? row.definition
            }
          />
          <span className="field-help">
            사전 정의와 이 논문에서의 뜻은 별개예요.
          </span>
          {candidate && (
            <span className="field-help">
              관측 {candidate.seen_count}회 · 연결 논문 {row.paper_count}편
            </span>
          )}
        </label>
        <section className="aliases">
          <div className="field-heading">
            <h3>영문 별칭</h3>
            <button
              disabled
              className="text-button"
              title="저장 연결 전에는 편집할 수 없어요"
            >
              추가
            </button>
          </div>
          <div className="alias-list">
            {aliases.length ? (
              aliases.map((a) => (
                <span className="alias-chip" key={a.alias_id}>
                  {a.surface_form}
                  <small>
                    {a.review_status === "approved" ? "승인" : "대기"}
                  </small>
                </span>
              ))
            ) : (
              <span className="micro subtle">등록된 별칭 없음</span>
            )}
          </div>
        </section>
        <section className="context-meaning">
          <h3>이 논문에서의 뜻</h3>
          <p>
            {context?.glossary?.definition_ko ??
              "연결된 적용 위치의 정의가 없어요."}
          </p>
        </section>
        <section className="related">
          <div className="field-heading">
            <h3>비슷한 표기</h3>
            <span className="micro subtle">자동 중복 판정 아님</span>
          </div>
          <button className="related-row" onClick={onRelated}>
            <span>다른 사전 의미 확인</span>
            <Icon name="arrow" size={14} />
          </button>
        </section>
        <label className="field note-field">
          현재 사전 검수 메모
          <textarea
            readOnly
            rows={2}
            value={sense?.review_note_ko ?? ""}
            placeholder="등록된 메모 없음"
          />
        </label>
      </div>
    </>
  );
}
