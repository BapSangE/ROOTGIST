import type { Sentence, Glossary, DisplaySense } from "./display";
export const capabilityNames = [
  "term_writes",
  "occurrence_writes",
  "paper_writes",
  "news_writes",
  "notice_publish",
  "notice_app_integration",
  "source_metadata_writes",
  "operations_history",
] as const;
export type Capabilities = Record<
  (typeof capabilityNames)[number],
  { enabled: boolean; reason: string | null }
>;
export type PageResult<T> = {
  rows: T[];
  next_cursor: string | null;
  total: number;
};
export type Revisioned<T> = { value: T; revision: number; base_sha256: string };
export type Sense = DisplaySense & {
  term_id: string;
  canonical_en: string;
  definition_ko: string | null;
  full_form_en: string | null;
  scope: string | null;
  domain: string | null;
  review_note_ko: string | null;
  source_media_review_required: boolean;
};
export type Alias = {
  alias_id: string;
  sense_id: string;
  surface_form: string;
  normalized_form: string | null;
  relation_type: string;
  review_status: string;
  auto_match_allowed: boolean;
};
export type Candidate = {
  normalized_form: string;
  surface_form: string;
  canonical_ko: string | null;
  canonical_ko_draft: string | null;
  definition_ko: string;
  review_status: string;
  seen_count: number;
  first_paper_id: string | null;
  sense_id: string | null;
  full_form_en: string | null;
  full_form_en_draft: string | null;
  draft_model: string | null;
  // 공식 소식·모델 글에서 온 후보(worker/glossary.py news_candidates): 처음 본 글과 문장
  source?: "paper" | "news";
  first_news_id?: string | null;
  context_ko?: string | null;
};
export type Paper = {
  id: string;
  title_en: string;
  title_ko: string | null;
  abstract_en: string;
  summary_ko: string | null;
  status: string;
  withdrawn: boolean;
  published_at: string;
  generated_at: string | null;
  model_id: string | null;
  prompt_version: string | null;
  schema_version: string | null;
  exposures: { date: string; is_exposed: boolean }[];
  sentences: Sentence[];
  glossary: Glossary[];
  key_points: {
    idx: number;
    claim_ko: string;
    evidence_sentence_ids: string[];
  }[];
};
export type News = {
  id: string;
  source: string;
  source_label: string;
  kind: string;
  category: string | null;
  title_en: string;
  title_ko: string | null;
  url: string;
  published_at: string;
  collected_at: string;
  summary_ko: string | null;
  thin: boolean;
  related: string[];
  key_points: { text: string; para: number | null; quote: string | null }[];
};
export type Model = {
  id: string;
  rank: number;
  author: string;
  name: string;
  task: string | null;
  params: number | null;
  license: string | null;
  likes: number | null;
  downloads: number | null;
  arxiv: string[];
  url: string;
  collected_at: string;
  card: {
    strengths: string[];
    benchmarks: { name: string; score: string }[];
    limitation: string | null;
  } | null;
};
export type Notice = {
  id: string;
  title: string;
  date: string;
  body: string;
  status: "bundled";
  origin: "app_bundle";
};
export type Source = {
  id: string;
  label: string;
  method: string;
  url: string;
  rights: string;
  reference: string;
};
export type Snapshot = {
  fixture: boolean;
  showAiReviewedTerms: boolean;
  senses: Sense[];
  aliases: Alias[];
  candidates: Candidate[];
  papers: Paper[];
  news: News[];
  models: Model[];
  notices: Notice[];
  sources: Source[];
  blockedUrls: string[];
  digests: {
    date: string;
    status: string;
    paper_count: number;
    last_success_at: string | null;
  }[];
  /** 용어 검수 기록(rootgist_admin). 용어 화면에서만 읽는다. 없으면 검수 기록 없음 */
  review?: ReviewMarks;
};
export type ReviewMarks = {
  writable: boolean;
  occurrences: { paper_id: string; idx: number; term: string; reviewed_at: string }[];
  controls: {
    entity_type: "sense" | "candidate" | "paper";
    entity_key: string;
    revision: number;
    review_state: string;
    note: string | null;
    updated_at: string;
  }[];
};
export type TermTargetState = { value: unknown; revision: number; base_sha256: string };
export type TermCommandResult = {
  operation_id: string;
  committed_at: string;
  targets: { entity_type: string; entity_key: string; revision: number; base_sha256: string }[];
  dictionary_sync_pending: boolean;
};
export type TermRow = {
  id: string;
  type: "candidate" | "sense" | "occurrence";
  term: string;
  canonical_ko: string | null;
  status: string;
  reviewed_at?: string | null; // 마지막 검수 저장 시각(검수 기록이 있을 때)
  review_note?: string | null; // 마지막 검수 메모·사유
  risk_count: number;
  risk_labels: string[];
  paper_id: string | null;
  idx: number | null;
  sense_id: string | null;
  seen_count: number | null;
  paper_count: number;
  definition: string;
};
export type Envelope = {
  fixture: boolean;
  capabilities: Capabilities;
  refreshed_at: string;
};
export type TermDetail = Revisioned<{
  row: TermRow;
  sense: Sense | null;
  candidate: Candidate | null;
  aliases: Alias[];
  papers: Paper[];
  all_senses: Sense[];
  show_ai_reviewed_terms: boolean;
}> &
  Envelope;
export type Dashboard = Envelope & {
  counts: {
    terms: number;
    risks: number;
    papers: number;
    news: number;
    failed: number;
  };
  priorities: TermRow[];
  recent: { id: string; title: string; kind: string; at: string }[];
  digests: Snapshot["digests"];
  operations: { state: "unconnected"; label: string };
};
