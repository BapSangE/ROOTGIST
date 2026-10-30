"use client";
import { useEffect, useEffectEvent, useRef, useState } from "react";
import type {
  Envelope,
  PageResult,
  TermDetail,
  TermRow,
  TermTargetState,
} from "@/lib/domain/contracts";
import { useReviewSave, type ReviewAction } from "./term-review-save";
import { listQuery } from "@/lib/domain/query";
import { findTerm, latexDisplay, normalizeTerm } from "@/lib/domain/display";
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
  // 기본은 「검토 필요」만: 끝낸 항목은 목록에서 빠져 다음 할 일만 남는다
  if (!query.has("filter")) query.set("filter", "pending");
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
  // ---- 사전 의미·후보 편집(항목마다 메모리에 보관, 저장하면 지운다) ----
  const row0 = detail.data?.value.row;
  const review = useReviewSave();
  const writable = !!detail.data?.capabilities.term_writes?.enabled;
  const meaningKey = JSON.stringify([row0?.type, row0?.id]);
  const [meaning, setMeaning] = useState<
    Record<string, { canonical_ko?: string; definition_ko?: string; note?: string }>
  >({});
  const senseValue = detail.data?.value.sense ?? null;
  const candidateValue = detail.data?.value.candidate ?? null;
  const baseKo =
    row0?.type === "candidate"
      ? (candidateValue?.canonical_ko ?? candidateValue?.canonical_ko_draft ?? "")
      : (senseValue?.canonical_ko ?? "");
  const baseDef =
    row0?.type === "candidate"
      ? (candidateValue?.definition_ko ?? "")
      : (senseValue?.definition_ko ?? "");
  const baseNote = row0?.type === "sense" ? (senseValue?.review_note_ko ?? "") : "";
  const edits = meaning[meaningKey] ?? {};
  const ko = edits.canonical_ko ?? baseKo,
    def = edits.definition_ko ?? baseDef,
    note = edits.note ?? baseNote;
  const meaningDirty =
    row0?.type !== "occurrence" && (ko !== baseKo || def !== baseDef || note !== baseNote);
  function editMeaning(field: "canonical_ko" | "definition_ko" | "note", value: string) {
    setMeaning((prev) => ({ ...prev, [meaningKey]: { ...prev[meaningKey], [field]: value } }));
  }
  const unsaved = dirty || meaningDirty;
  function navigate(v: Changes) {
    if (unsaved) {
      setIntent(v);
      return;
    }
    setAssume(false);
    setDrawer(null);
    review.reset(); // 직접 다른 항목으로 가면 지난 저장 알림은 지운다(저장 뒤 자동 이동 때는 남긴다)
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
  const hasDraft = Object.keys(drafts).length > 0 || meaningDirty;
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
    if (discard) {
      setDrafts((prev) => {
        const next = { ...prev };
        delete next[draftKey];
        return next;
      });
      setMeaning((prev) => {
        const next = { ...prev };
        delete next[meaningKey];
        return next;
      });
    }
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
      editable={!!writable && detail.data.value.row.type !== "occurrence"}
      values={{ ko, def, note }}
      onEdit={editMeaning}
      onOpenSense={(type, id) => navigate({ type, id, paper: null, sentence: null, filter: "all" })}
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
  const linkedSentence = !!ctx?.glossary?.sentence_ids.includes(
    ctx.sentence?.id ?? "",
  );
  // ---- 검수 저장 ----
  const entity =
    row?.type === "occurrence"
      ? { entity_type: "paper" as const, entity_key: row.paper_id ?? "" }
      : row?.type === "sense"
        ? { entity_type: "sense" as const, entity_key: row.sense_id ?? row.id }
        : row
          ? { entity_type: "candidate" as const, entity_key: row.id }
          : null;
  const target = useResource<TermTargetState>(
    entity && writable
      ? `/api/admin/v1/term-target/${entity.entity_type}/${encodeURIComponent(entity.entity_key)}`
      : null,
  );
  const [doneCount, setDoneCount] = useState(0);
  const [problem, setProblem] = useState<{ key: string; message: string } | null>(null);
  const [armed, setArmed] = useState<string | null>(null); // 반려는 두 번 눌러야 한다
  const [lastAction, setLastAction] = useState<ReviewAction>("apply_patch");
  const itemProblem = problem?.key === meaningKey ? problem.message : null;
  const spanInLinked =
    !ctx?.span ||
    !!ctx?.texts.some(
      (t) => ctx.glossary?.sentence_ids.includes(t.id) && (t.translation ?? "").includes(ctx.span!),
    );
  function patchFor(): Record<string, unknown> {
    if (!row || !ctx) return {};
    if (row.type === "occurrence")
      return {
        glossary: [{ idx: ctx.glossary!.idx, expected_term: ctx.glossary!.term, ko_span: ctx.span || null }],
      };
    const patch: Record<string, unknown> = {};
    if (row.type === "candidate") {
      if (ko !== (candidateValue?.canonical_ko ?? "")) patch.canonical_ko = ko.trim() || null;
      if (def !== baseDef) patch.definition_ko = def;
    } else {
      if (ko !== baseKo) patch.canonical_ko = ko.trim() || null;
      if (def !== baseDef) patch.definition_ko = def.trim() || null;
      if (note !== baseNote) patch.review_note_ko = note.trim() || null;
    }
    return patch;
  }
  function blocker(action: ReviewAction): string | null {
    if (!writable) return "저장 연결이 꺼져 있어요.";
    if (!target.data) return "원본 상태를 불러오는 중이에요. 잠시 후 다시 눌러 주세요.";
    if (row?.type === "occurrence") {
      if (!ctx?.glossary) return "이 논문에서 용어 행을 찾지 못했어요.";
      if (!spanInLinked) return "강조할 표기가 연결 문장 번역문에 없어요. 번역문에 있는 글자로 바꿔 주세요.";
    } else if (action === "approve") {
      if (!ko.trim()) return "한국어 표기를 채워야 승인할 수 있어요.";
      if (row?.type === "sense" && !def.trim()) return "일반 정의를 채워야 승인할 수 있어요.";
    }
    if (action === "needs_changes" && !note.trim() && row?.type !== "occurrence")
      return "무엇을 고쳐야 하는지 메모를 남겨 주세요.";
    return null;
  }
  const actionLabel: Record<ReviewAction, string> = {
    apply_patch: row?.type === "occurrence" ? "적용 위치를 확인했어요" : "변경을 저장했어요",
    approve: row?.type === "candidate" ? "후보를 승인했어요" : "의미를 승인했어요",
    reject: "반려했어요",
    needs_changes: "수정 필요로 표시했어요",
  };
  async function submit(action: ReviewAction, advance = true) {
    if (!row || !entity || review.state.kind === "saving") return;
    const why = blocker(action);
    if (why) {
      setProblem({ key: meaningKey, message: why });
      return;
    }
    if (action === "reject" && armed !== meaningKey) {
      setArmed(meaningKey);
      return;
    }
    setProblem(null);
    setArmed(null);
    setLastAction(action);
    const nextId = list.data?.rows[index + 1]?.id ?? null;
    const result = await review.save(action, { ...entity, patch: patchFor() }, target.data!, note.trim(), actionLabel[action]);
    target.retry();
    if (!result) {
      detail.retry();
      return;
    }
    setDrafts((prev) => {
      const next = { ...prev };
      delete next[draftKey];
      return next;
    });
    setMeaning((prev) => {
      const next = { ...prev };
      delete next[meaningKey];
      return next;
    });
    setDoneCount((n) => n + 1);
    list.retry();
    detail.retry();
    if (advance) {
      setAssume(false);
      setDrawer(null);
      change({ id: nextId, paper: null, sentence: null });
      requestAnimationFrame(() => document.getElementById("content")?.focus());
    }
  }
  function submitPrimary() {
    if (!row) return;
    submit(row.type === "occurrence" ? "apply_patch" : "approve");
  }
  const primary = useEffectEvent(() => submitPrimary());
  useEffect(() => {
    function key(e: KeyboardEvent) {
      if (document.querySelector("dialog[open]")) return;
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
        e.preventDefault();
        primary();
        return;
      }
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
  function setSpan(value: string) {
    setDrafts((prev) => {
      const next = { ...prev };
      if (value === (base?.span ?? "")) delete next[draftKey];
      else next[draftKey] = value;
      return next;
    });
  }
  const [picked, setPicked] = useState<{ key: string; text: string } | null>(null);
  const pickedText = picked?.key === draftKey ? picked.text : null;
  function pickFromTranslation() {
    const text = window.getSelection()?.toString().trim() ?? "";
    const translation = ctx?.sentence?.translation ?? "";
    setPicked(text && text.length <= 60 && translation.includes(text) ? { key: draftKey, text } : null);
  }
  const suggestions = (ctx?.labels ?? []).filter(
    (l) => l !== (ctx?.span ?? "") && findTerm(ctx?.sentence?.translation ?? "", l) >= 0,
  );
  const busy = review.state.kind === "saving";
  const tone =
    review.state.kind === "error" ? "bad" : review.state.kind === "saved" ? "good" : unsaved ? "warn" : "";
  const statusText =
    review.state.kind === "saving"
      ? "저장 중…"
      : review.state.kind === "saved"
        ? `${review.state.label} · ${new Date(review.state.at).toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit" })}${
            review.state.syncPending ? " · 사전에는 다음 배치(02:17)에 들어가요" : ""
          }`
        : review.state.kind === "error"
          ? review.state.message
          : unsaved
            ? "저장하지 않은 변경이 있어요"
            : !detail.data
              ? "불러오는 중이에요"
              : writable
                ? `이번에 ${doneCount}개 검수했어요`
                : "조회 전용 · 저장 연결을 확인해 주세요";
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
          {fixture ? "가상 데이터 · 로컬 검토본" : writable ? "실제 데이터 · 저장 가능" : "실제 데이터 · 조회 전용"}
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
                    : params.get("query")
                      ? "검색 결과가 없어요"
                      : (params.get("filter") ?? "pending") === "pending"
                        ? "이 칸은 모두 검수했어요. 다른 칸이나 「수정 필요」를 확인해 보세요."
                        : "해당하는 항목이 없어요"
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
                    aria-label="한국어 번역 문장 · 글자를 드래그해 강조 표기로 고를 수 있어요"
                    onMouseUp={pickFromTranslation}
                    onKeyUp={pickFromTranslation}
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
                      disabled={!ctx.glossary || row?.type !== "occurrence"}
                      title={row?.type !== "occurrence" ? "강조 표기는 「적용 위치」 칸에서 고쳐요" : undefined}
                      placeholder="미지정 · 사전 대응어 또는 영문 표기로 찾아요"
                      aria-describedby="matchInfo"
                      onChange={(e) => setSpan(e.target.value)}
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
                {row?.type === "occurrence" && (suggestions.length > 0 || pickedText) && (
                  <div className="span-suggestions" aria-label="번역문에서 고르기">
                    <span className="micro subtle">번역문에 있는 표기</span>
                    {pickedText && (
                      <button className="suggestion picked" onClick={() => { setSpan(pickedText); setPicked(null); }}>
                        선택한 「{pickedText}」
                      </button>
                    )}
                    {suggestions.map((l) => (
                      <button key={l} className="suggestion" onClick={() => setSpan(l)}>
                        {l}
                      </button>
                    ))}
                  </div>
                )}
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
                      focusIdx={ctx.glossary?.idx ?? null}
                      names={Object.fromEntries((ctx.projection?.terms ?? []).map((t) => [t.idx, t.term]))}
                    />
                  </p>
                </div>
                {/* 같은 문장에서 함께 강조되는 다른 용어: 붙어 있으면 한 덩어리처럼 보여 따로 적는다. 누르면 그 적용 위치로 */}
                {(() => {
                  const others = (ctx.projection?.ko[ctx.sentence?.id ?? ""] ?? []).filter(
                    (h) => h.idx !== ctx.glossary?.idx,
                  );
                  return others.length && ctx.paper ? (
                    <div className="preview-others">
                      <span className="micro subtle">
                        <i className="swatch current" /> 지금 검토 중 · <i className="swatch other" /> 이 문장의 다른 용어
                      </span>
                      {others.map((h) => {
                        const t = ctx.projection!.terms.find((x) => x.idx === h.idx);
                        return (
                          <button
                            key={h.idx}
                            className="suggestion"
                            onClick={() =>
                              navigate({
                                type: "occurrence",
                                id: JSON.stringify({ paper_id: ctx.paper!.id, idx: h.idx }),
                                paper: null,
                                sentence: null,
                                filter: "all",
                              })
                            }
                          >
                            {t?.term} · {h.label}
                          </button>
                        );
                      })}
                    </div>
                  ) : null;
                })()}
                <div className="preview-foot">
                  {assume ? "승인 가정 · 실제 검토 상태는 바뀌지 않아요. " : ""}
                  {ctx.matchCount > 1 ? "같은 표기는 첫 일치만 강조해요. " : ""}
                  {!ctx.span ? "빈 표기는 사전 대응어, 그다음 번역문에 남은 영문 표기로 찾아요. " : ""}
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
        <div className="action-note" role="status" aria-live="polite">
          <span className={`dot ${tone}`} />
          <span>{itemProblem ?? statusText}</span>
          {review.state.kind === "error" && review.state.retryable && (
            <button className="text-button" onClick={() => submit(lastAction)} disabled={busy}>
              다시 시도
            </button>
          )}
        </div>
        <div className="actions">
          {row?.type === "occurrence" || !row ? (
            <>
              <button className="button secondary" onClick={() => move(1)} disabled={!canNext || busy}>
                건너뛰기
              </button>
              <button
                className="button primary"
                onClick={() => submit("apply_patch")}
                disabled={!writable || busy || !ctx?.glossary}
                title={writable ? "이 표기로 확인하고 다음 항목으로 (⌘/Ctrl+Enter)" : "저장 연결을 확인해 주세요"}
              >
                {busy ? "저장 중…" : "확인하고 다음"} <kbd>⌘↵</kbd>
              </button>
            </>
          ) : (
            <>
              <button
                className={`quiet ${armed === meaningKey ? "danger" : ""}`}
                onClick={() => submit("reject")}
                disabled={!writable || busy}
              >
                {armed === meaningKey ? "한 번 더 누르면 반려" : "반려"}
              </button>
              <button className="button secondary" onClick={() => submit("needs_changes")} disabled={!writable || busy}>
                수정 필요
              </button>
              {meaningDirty && (
                <button className="button secondary" onClick={() => submit("apply_patch", false)} disabled={!writable || busy}>
                  저장만
                </button>
              )}
              <button
                className="button primary"
                onClick={() => submit("approve")}
                disabled={!writable || busy}
                title={writable ? "승인하고 다음 항목으로 (⌘/Ctrl+Enter)" : "저장 연결을 확인해 주세요"}
              >
                {busy ? "저장 중…" : "승인하고 다음"} <kbd>⌘↵</kbd>
              </button>
            </>
          )}
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
            <b>적용 위치</b>: 번역문에서 강조할 표기를 고르고(칩을 누르거나 번역문을 드래그) 「확인하고 다음」.
            앱 표시 예상의 노란 강조가 실제 앱과 같은 규칙이에요.
          </p>
          <p>
            <b>사전 의미·후보</b>: 한국어 표기와 일반 정의를 다듬고 「승인하고 다음」. 고칠 점이 있으면 메모를 남기고
            「수정 필요」, 쓰지 않을 용어는 「반려」(두 번 눌러요). 후보를 승인하면 다음 배치(02:17)에 사전에 들어가요.
          </p>
          <p>
            <kbd>⌘</kbd>/<kbd>Ctrl</kbd>+<kbd>Enter</kbd> 확인·승인하고 다음 · <kbd>J</kbd>/<kbd>K</kbd> 다음/이전 ·{" "}
            <kbd>/</kbd> 검색. 입력 중에는 J/K가 글자로 들어가요.
          </p>
          <p>
            저장한 값은 배치가 덮어쓰지 않아요. 논문이 다시 만들어지면 그 적용 위치만 「검토 필요」로 돌아와요.
            「승인 가정」은 미리보기일 뿐 실제 상태를 바꾸지 않아요.
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
            value={params.get("filter") ?? "pending"}
            onChange={(e) =>
              onNavigate({
                filter: e.target.value,
                id: null,
                paper: null,
                sentence: null,
              })
            }
          >
            <option value="pending">검토 필요</option>
            <option value="risks">적용 위험 우선</option>
            <option value="deferred">수정 필요</option>
            <option value="approved">검수 완료</option>
            <option value="all">전체</option>
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
          <StatePanel
            empty={
              params.get("query")
                ? "검색 결과가 없어요"
                : (params.get("filter") ?? "pending") === "pending"
                  ? "모두 검수했어요"
                  : "해당하는 항목이 없어요"
            }
          />
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
  editable,
  values,
  onEdit,
  onOpenSense,
}: {
  detail: TermDetail;
  context: ReturnType<typeof reviewContext> | null;
  onRelated: () => void;
  editable: boolean;
  values: { ko: string; def: string; note: string };
  onEdit: (field: "canonical_ko" | "definition_ko" | "note", value: string) => void;
  onOpenSense: (type: "sense" | "candidate", id: string) => void;
}) {
  const { row, sense, candidate, aliases } = detail.value;
  const occurrence = row.type === "occurrence";
  return (
    <>
      <div className="inspector-heading">
        <h2>{candidate ? "후보" : "사전 의미"}</h2>
        <span className="scope-label">
          {occurrence
            ? "여러 논문에 적용 · 여기서는 보기만"
            : editable
              ? "여러 논문에 적용 · 고치면 다시 승인해야 해요"
              : "여러 논문에 적용 · 조회"}
        </span>
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
        {occurrence && (
          <button
            className="related-row open-sense"
            onClick={() => (sense ? onOpenSense("sense", sense.sense_id) : onOpenSense("candidate", normalizeTerm(row.term)))}
          >
            <span>{sense ? "이 의미 검수하러 가기" : "사전에 없는 용어 · 후보 검수하러 가기"}</span>
            <Icon name="arrow" size={14} />
          </button>
        )}
        <label className="field">
          {candidate && !candidate.canonical_ko ? "한국어 표기 · AI 제안으로 채웠어요" : "한국어 표기"}
          <input
            readOnly={!editable}
            value={occurrence ? (sense?.canonical_ko ?? row.canonical_ko ?? "") : values.ko}
            onChange={(e) => onEdit("canonical_ko", e.target.value)}
            placeholder={occurrence ? "사전 의미에 연결되지 않았어요" : "예: 동결된 디코더"}
          />
        </label>
        <label className="field definition-field">
          일반 정의
          <textarea
            readOnly={!editable}
            rows={4}
            value={occurrence ? (sense?.definition_ko ?? row.definition) : values.def}
            onChange={(e) => onEdit("definition_ko", e.target.value)}
          />
          <span className="field-help">
            앱의 공식 소식·모델 상세 용어 설명에 쓰여요. 이 논문에서의 뜻은 아래에 따로 있어요.
          </span>
          {candidate && (
            <span className="field-help">
              {candidate.source === "news"
                ? `소식·모델 글 ${candidate.seen_count}곳 · 승인하면 다음 배치에 사전에 들어가요`
                : `관측 ${candidate.seen_count}회 · 연결 논문 ${row.paper_count}편 · 승인하면 다음 배치에 사전에 들어가요`}
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
        {candidate?.source === "news" ? (
          <section className="context-meaning">
            <h3>처음 나온 소식 문장</h3>
            <p>{candidate.context_ko ?? "문장을 남기지 못했어요."}</p>
          </section>
        ) : (
          <section className="context-meaning">
            <h3>이 논문에서의 뜻</h3>
            <p>
              {context?.glossary?.definition_ko ??
                "연결된 적용 위치의 정의가 없어요."}
            </p>
          </section>
        )}
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
          검수 메모
          <textarea
            readOnly={!editable}
            rows={2}
            value={occurrence ? (sense?.review_note_ko ?? "") : values.note}
            onChange={(e) => onEdit("note", e.target.value)}
            placeholder={editable ? "「수정 필요」에는 고칠 점을 적어 주세요" : "등록된 메모 없음"}
          />
          {row.review_note && <span className="field-help">마지막 검수 사유: {row.review_note}</span>}
        </label>
      </div>
    </>
  );
}
