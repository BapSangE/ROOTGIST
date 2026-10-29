import { createHash } from "node:crypto";
import type {
  Snapshot,
  TermRow,
  PageResult,
  TermDetail,
  Capabilities,
  Envelope,
  Dashboard,
} from "@/lib/domain/contracts";
import { capabilityNames } from "@/lib/domain/contracts";
import { normalizeTerm } from "@/lib/domain/display";
import { AdminError } from "./errors";
export function capabilities(): Capabilities {
  return Object.fromEntries(
    capabilityNames.map((name) => [
      name,
      {
        enabled: false,
        reason:
          name === "notice_app_integration"
            ? "현재 앱은 번들 공지를 읽습니다. 새 앱 연결이 필요합니다."
            : name === "operations_history"
              ? "실행별 계측이 아직 연결되지 않았습니다."
              : "수정본 보호·초안·저장 경로 검증 후 사용할 수 있습니다.",
      },
    ]),
  ) as Capabilities;
}
export function envelope(s: Snapshot): Envelope {
  return {
    fixture: s.fixture,
    capabilities: capabilities(),
    refreshed_at: new Date().toISOString(),
  };
}
function missing(): never {
  throw new AdminError(
    404,
    "ENTITY_NOT_FOUND",
    "항목이 없거나 목록이 변경되었습니다.",
  );
}
function invalid(message: string): never {
  throw new AdminError(422, "VALIDATION_FAILED", message);
}
export function revisioned<T>(value: T) {
  return {
    value,
    revision: 0,
    base_sha256: createHash("sha256")
      .update(JSON.stringify(value))
      .digest("hex"),
  };
}
export function paginate<T extends { id: string }>(
  rows: T[],
  params: URLSearchParams,
): PageResult<T> {
  const filter = [...params.entries()]
    .filter(([k]) => !["cursor", "id", "paper", "sentence"].includes(k))
    .sort();
  const fingerprint = createHash("sha256")
    .update(JSON.stringify([filter, rows.map((r) => r.id)]))
    .digest("hex");
  let offset = 0;
  if (params.get("cursor")) {
    try {
      const cursor = JSON.parse(
        Buffer.from(params.get("cursor")!, "base64url").toString("utf8"),
      );
      if (
        cursor.fingerprint !== fingerprint ||
        !Number.isInteger(cursor.offset) ||
        cursor.offset < 0 ||
        cursor.offset >= rows.length
      )
        throw new Error();
      offset = cursor.offset;
    } catch {
      invalid("목록 조건이 바뀌었습니다. 첫 페이지부터 다시 확인해 주세요.");
    }
  }
  const size = params.has("limit") ? Number(params.get("limit")) : 50;
  if (!Number.isInteger(size) || size < 1 || size > 50)
    invalid("목록 크기는 1~50 사이여야 합니다.");
  const next = offset + size;
  return {
    rows: rows.slice(offset, next),
    total: rows.length,
    next_cursor:
      next < rows.length
        ? Buffer.from(JSON.stringify({ fingerprint, offset: next })).toString(
            "base64url",
          )
        : null,
  };
}
export function termRows(s: Snapshot): TermRow[] {
  const rows: TermRow[] = [];
  for (const paper of s.papers)
    for (const g of paper.glossary) {
      const sense = s.senses.find((x) => x.sense_id === g.sense_id);
      const texts = paper.sentences
        .filter((x) => x.kind === "text" && g.sentence_ids.includes(x.id))
        .map((x) => x.translation ?? "");
      const risks: string[] = [];
      if (!g.sense_id) risks.push("사전 의미 미연결");
      if (g.ko_span === null) risks.push("적용 위치 미확인");
      else if (
        g.ko_span &&
        !texts.some((t) => t.includes(g.ko_span!.replace(/\s*\(.*\)$/, "")))
      )
        risks.push("번역문 표기 불일치");
      else if (
        g.ko_span &&
        texts.reduce((n, t) => n + t.split(g.ko_span!).length - 1, 0) > 1
      )
        risks.push("같은 표기 여러 곳");
      rows.push({
        id: JSON.stringify({ paper_id: paper.id, idx: g.idx }),
        type: "occurrence",
        term: g.term,
        canonical_ko: sense?.canonical_ko ?? null,
        status: "unreviewed",
        risk_count: risks.length,
        risk_labels: risks,
        paper_id: paper.id,
        idx: g.idx,
        sense_id: g.sense_id,
        seen_count: null,
        paper_count: 1,
        definition: g.definition_ko,
      });
    }
  for (const sense of s.senses) {
    const related = rows.filter((r) => r.sense_id === sense.sense_id);
    rows.push({
      id: sense.sense_id,
      type: "sense",
      term: sense.canonical_en,
      canonical_ko: sense.canonical_ko,
      status: sense.review_status,
      risk_count: related.reduce((n, r) => n + r.risk_count, 0),
      risk_labels: [...new Set(related.flatMap((r) => r.risk_labels))],
      paper_id: null,
      idx: null,
      sense_id: sense.sense_id,
      seen_count: null,
      paper_count: new Set(related.map((r) => r.paper_id)).size,
      definition: sense.definition_ko ?? "",
    });
  }
  for (const candidate of s.candidates.filter((c) => !c.sense_id)) {
    const related = rows.filter(
      (r) =>
        r.type === "occurrence" &&
        normalizeTerm(r.term) === candidate.normalized_form,
    );
    rows.push({
      id: candidate.normalized_form,
      type: "candidate",
      term: candidate.surface_form,
      canonical_ko: candidate.canonical_ko ?? candidate.canonical_ko_draft,
      status: candidate.review_status,
      risk_count: related.reduce((n, r) => n + r.risk_count, 0),
      risk_labels: [...new Set(related.flatMap((r) => r.risk_labels))],
      paper_id: candidate.first_paper_id,
      idx: null,
      sense_id: null,
      seen_count: candidate.seen_count,
      paper_count: new Set(related.map((r) => r.paper_id)).size,
      definition: candidate.definition_ko,
    });
  }
  return rows.sort(
    (a, b) =>
      (b.risk_count > 0 ? 1 : 0) - (a.risk_count > 0 ? 1 : 0) ||
      ({ deferred: 0, pending: 1, unreviewed: 1, approved: 2, rejected: 3 }[
        a.status
      ] ?? 4) -
        ({ deferred: 0, pending: 1, unreviewed: 1, approved: 2, rejected: 3 }[
          b.status
        ] ?? 4) ||
      a.id.localeCompare(b.id),
  );
}
export function listTerms(s: Snapshot, params: URLSearchParams) {
  const query = params.get("query")?.trim().toLowerCase() ?? "";
  if (query.length > 120) invalid("검색어는 120자 이하로 입력해 주세요.");
  const type = params.get("type");
  if (type && !["all", "sense", "candidate", "occurrence"].includes(type))
    invalid("올바른 목록 종류를 선택해 주세요.");
  const status = params.get("filter");
  if (
    status &&
    !["all", "pending", "approved", "rejected", "deferred", "risks"].includes(
      status,
    )
  )
    invalid("올바른 필터를 선택해 주세요.");
  const rows = termRows(s).filter(
    (r) =>
      (!type || type === "all" || r.type === type) &&
      (!query ||
        `${r.term} ${r.canonical_ko ?? ""}`.toLowerCase().includes(query)) &&
      (!status ||
        status === "all" ||
        (status === "risks"
          ? r.risk_count > 0
          : status === "pending"
            ? ["pending", "unreviewed"].includes(r.status)
            : r.status === status)),
  );
  return { ...envelope(s), ...paginate(rows, params) };
}
export function termDetail(s: Snapshot, type: string, id: string): TermDetail {
  const row =
    termRows(s).find((r) => r.type === type && r.id === id) ?? missing();
  const sense = s.senses.find((x) => x.sense_id === row.sense_id) ?? null;
  const candidate =
    row.type === "candidate"
      ? (s.candidates.find((c) => c.normalized_form === id) ?? null)
      : null;
  const papers = s.papers.filter((p) =>
    row.type === "occurrence"
      ? p.id === row.paper_id
      : row.type === "sense"
        ? p.glossary.some((g) => g.sense_id === id)
        : p.glossary.some((g) => normalizeTerm(g.term) === id) ||
          p.id === candidate?.first_paper_id,
  );
  return {
    ...envelope(s),
    ...revisioned({
      row,
      sense,
      candidate,
      aliases: s.aliases.filter((a) => a.sense_id === sense?.sense_id),
      papers,
      all_senses: s.senses,
      show_ai_reviewed_terms: s.showAiReviewedTerms,
    }),
  };
}
export function dashboard(s: Snapshot): Dashboard {
  const rows = termRows(s);
  return {
    ...envelope(s),
    counts: {
      terms: rows.filter(
        (r) => r.type !== "occurrence" && r.status === "pending",
      ).length,
      risks: rows.filter((r) => r.type === "occurrence" && r.risk_count > 0)
        .length,
      papers: s.papers.length,
      news: s.news.length,
      failed: s.papers.filter((p) => p.status === "failed").length,
    },
    priorities: rows
      .filter((r) => r.type === "occurrence" && r.risk_count > 0)
      .slice(0, 4),
    recent: [
      ...s.papers.map((p) => ({
        id: p.id,
        title: p.title_ko ?? p.title_en,
        kind: "논문",
        at: p.published_at,
      })),
      ...s.news.map((n) => ({
        id: n.id,
        title: n.title_ko ?? n.title_en,
        kind: "공식 소식",
        at: n.published_at,
      })),
    ]
      .sort((a, b) => b.at.localeCompare(a.at))
      .slice(0, 5),
    digests: s.digests,
    operations: { state: "unconnected", label: "실행 이력 연동 필요" },
  };
}
export function readResource(
  s: Snapshot,
  path: string[],
  params: URLSearchParams,
): unknown {
  if (path.length === 1 && path[0] === "dashboard") return dashboard(s);
  if (path[0] === "terms")
    return path.length === 3
      ? termDetail(s, path[1], path[2])
      : path.length === 1
        ? listTerms(s, params)
        : missing();
  const collections = {
    papers: s.papers,
    news: s.news,
    models: s.models,
    notices: s.notices,
  };
  if (path[0] in collections) {
    const values = collections[path[0] as keyof typeof collections];
    if (path.length === 2) {
      const value = values.find((x) => x.id === path[1]) ?? missing();
      return {
        ...envelope(s),
        ...revisioned(value),
        all_senses: path[0] === "papers" ? s.senses : undefined,
        show_ai_reviewed_terms: s.showAiReviewedTerms,
      };
    }
    if (path.length !== 1) missing();
    const query = params.get("query")?.toLowerCase() ?? "";
    if (query.length > 120) invalid("검색어는 120자 이하로 입력해 주세요.");
    const rows = values.filter(
      (v) =>
        (!query || JSON.stringify(v).toLowerCase().includes(query)) &&
        (!params.get("source") ||
          ("source" in v && v.source === params.get("source"))) &&
        (!params.get("kind") || ("kind" in v && v.kind === params.get("kind"))),
    );
    return {
      ...envelope(s),
      ...paginate(rows, params),
      ...(path[0] === "news"
        ? {
            source_options: [
              ...new Map(
                s.news.map((n) => [
                  n.source,
                  { id: n.source, label: n.source_label },
                ]),
              ).values(),
            ].sort((a, b) => a.id.localeCompare(b.id)),
          }
        : {}),
    };
  }
  if (path.length === 1 && path[0] === "sources")
    return {
      ...envelope(s),
      rows: s.sources,
      blocked_urls: s.blockedUrls,
      catalog_baseline: "b8e5c6a",
    };
  if (path.length === 2 && path[0] === "operations" && path[1] === "runs")
    return {
      ...envelope(s),
      state: "unconnected",
      rows: [],
      label: "실행 이력 연동 필요",
      scheduled_at: "KST 02:17", // .github/workflows/daily-batch.yml cron "17 17 * * *". 바꾸면 같이 고친다
      digests: s.digests,
    };
  return missing();
}
