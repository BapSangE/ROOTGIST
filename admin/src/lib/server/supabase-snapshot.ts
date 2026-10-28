import "server-only";
import type {
  Snapshot,
  Sense,
  Candidate,
  Alias,
  News,
  Model,
  Paper,
} from "@/lib/domain/contracts";
import type { AdminIdentity } from "./auth-policy";
import { privilegedReadClient } from "@/lib/supabase/privileged";
import { AdminError } from "./errors";
import catalog from "./source-catalog.json";
import notices from "./notices-snapshot.json";
type Row = Record<string, unknown>;
const specs = {
  terms: ["term_id,canonical_en", "term_id"],
  term_senses: [
    "sense_id,term_id,canonical_ko,definition_ko,scope,domain,definition_kind,ai_review_status,review_status,source_media_review_required,review_note_ko,full_form_en",
    "sense_id",
  ],
  term_aliases: [
    "alias_id,sense_id,surface_form,normalized_form,relation_type,review_status,auto_match_allowed",
    "alias_id",
  ],
  term_candidates: [
    "normalized_form,surface_form,canonical_ko,canonical_ko_draft,definition_ko,review_status,seen_count,first_paper_id,sense_id,full_form_en,full_form_en_draft,draft_model",
    "normalized_form",
  ],
  papers: ["paper_id,title_en,abstract_en,published_at,withdrawn", "paper_id"],
  paper_ai: [
    "paper_id,status,title_ko,summary_ko,generated_at,model_id,prompt_version,schema_version",
    "paper_id",
  ],
  paper_sentences: [
    "paper_id,sentence_id,start_offset,end_offset,kind",
    "paper_id,sentence_id",
  ],
  paper_translations: [
    "paper_id,sentence_id,translation_ko",
    "paper_id,sentence_id",
  ],
  paper_glossary: [
    "paper_id,idx,term,definition_ko,context_ko,sentence_ids,highlight,sense_id,ko_span,full_form_en",
    "paper_id,idx",
  ],
  paper_key_points: [
    "paper_id,idx,claim_ko,evidence_sentence_ids",
    "paper_id,idx",
  ],
  official_news: [
    "id,source,source_label,kind,category,title_en,title_ko,url,published_at,collected_at,summary_ko,key_points,thin,related",
    "id",
  ],
  trending_models: [
    "id,rank,author,name,task,params,license,likes,downloads,arxiv,url,collected_at,card",
    "id",
  ],
  digests: ["digest_date,status,paper_count,last_success_at", "digest_date"],
  digest_papers: ["digest_date,paper_id,is_exposed", "digest_date,paper_id"],
  app_config: ["key,value", "key"],
  worker_state: ["key,value", "key"],
} as const;
const str = (r: Row, k: string) =>
  typeof r[k] === "string" ? (r[k] as string) : "";
const nullable = (r: Row, k: string) =>
  typeof r[k] === "string" ? (r[k] as string) : null;
const number = (r: Row, k: string) =>
  typeof r[k] === "number" ? (r[k] as number) : 0;
export async function supabaseSnapshot(
  actor: AdminIdentity,
): Promise<Snapshot> {
  const client = privilegedReadClient(actor);
  const results = await Promise.all(
    Object.entries(specs).map(async ([table, [columns, order]]) => {
      const rows: Row[] = [];
      let total = 0;
      for (let from = 0; from === 0 || from < total; from += 500) {
        let query = client.from(table).select(columns, { count: "exact" });
        if (table === "worker_state") query = query.eq("key", "blocked_urls");
        if (table === "app_config")
          query = query.eq("key", "show_ai_reviewed_terms");
        for (const key of order.split(","))
          query = query.order(key, { ascending: true });
        const { data, count, error } = await query.range(from, from + 499);
        if (error || count === null || count > 10000)
          throw new AdminError(
            503,
            "DEPENDENCY_UNAVAILABLE",
            "조회에 실패했거나 R0 조회 범위를 넘었습니다. 전용 조회 연동을 확인해 주세요.",
          );
        total = count;
        const page = data as unknown as Row[];
        if (!page.length && rows.length < total)
          throw new AdminError(
            503,
            "DEPENDENCY_UNAVAILABLE",
            "조회 중 데이터가 바뀌었습니다. 다시 불러와 주세요.",
          );
        rows.push(...page);
      }
      return [table, rows] as const;
    }),
  );
  const tables = Object.fromEntries(results) as Record<
    keyof typeof specs,
    Row[]
  >;
  const senses = tables.term_senses.map((r) => ({
    ...r,
    canonical_en: str(
      tables.terms.find((t) => t.term_id === r.term_id) ?? {},
      "canonical_en",
    ),
  })) as unknown as Sense[];
  const papers: Paper[] = tables.papers.map((p) => {
    const id = str(p, "paper_id");
    const ai = tables.paper_ai.find((r) => r.paper_id === id) ?? {};
    const abstract = str(p, "abstract_en");
    return {
      id,
      title_en: str(p, "title_en"),
      title_ko: nullable(ai, "title_ko"),
      summary_ko: nullable(ai, "summary_ko"),
      abstract_en: abstract,
      status: str(ai, "status") || "pending",
      withdrawn: p.withdrawn === true,
      published_at: str(p, "published_at"),
      generated_at: nullable(ai, "generated_at"),
      model_id: nullable(ai, "model_id"),
      prompt_version: nullable(ai, "prompt_version"),
      schema_version: nullable(ai, "schema_version"),
      exposures: tables.digest_papers
        .filter((r) => r.paper_id === id)
        .map((r) => ({
          date: str(r, "digest_date"),
          is_exposed: r.is_exposed === true,
        })),
      sentences: tables.paper_sentences
        .filter((r) => r.paper_id === id)
        .sort((a, b) => number(a, "start_offset") - number(b, "start_offset"))
        .map((r) => ({
          id: str(r, "sentence_id"),
          kind: str(r, "kind"),
          start_offset: number(r, "start_offset"),
          text: Array.from(abstract)
            .slice(number(r, "start_offset"), number(r, "end_offset"))
            .join(""),
          translation: nullable(
            tables.paper_translations.find(
              (t) => t.paper_id === id && t.sentence_id === r.sentence_id,
            ) ?? {},
            "translation_ko",
          ),
        })),
      glossary: tables.paper_glossary
        .filter((r) => r.paper_id === id)
        .sort(
          (a, b) => number(a, "idx") - number(b, "idx"),
        ) as unknown as Paper["glossary"],
      key_points: tables.paper_key_points
        .filter((r) => r.paper_id === id)
        .sort(
          (a, b) => number(a, "idx") - number(b, "idx"),
        ) as unknown as Paper["key_points"],
    };
  });
  const blocked = tables.worker_state.find((r) => r.key === "blocked_urls")
    ?.value as { urls?: unknown } | undefined;
  return {
    fixture: false,
    showAiReviewedTerms: tables.app_config.some(
      (r) => r.key === "show_ai_reviewed_terms" && r.value === "true",
    ),
    senses,
    aliases: tables.term_aliases as unknown as Alias[],
    candidates: tables.term_candidates as unknown as Candidate[],
    papers,
    news: tables.official_news as unknown as News[],
    models: tables.trending_models as unknown as Model[],
    notices: notices.rows as Snapshot["notices"],
    sources: catalog.rows,
    blockedUrls: Array.isArray(blocked?.urls)
      ? blocked.urls.filter((x): x is string => typeof x === "string")
      : [],
    digests: tables.digests.map((r) => ({
      date: str(r, "digest_date"),
      status: str(r, "status"),
      paper_count: number(r, "paper_count"),
      last_success_at: nullable(r, "last_success_at"),
    })),
  };
}
