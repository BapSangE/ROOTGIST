export type Sentence = {
  id: string;
  kind: string;
  start_offset: number;
  text: string;
  translation: string | null;
};
export type Glossary = {
  idx: number;
  term: string;
  definition_ko: string;
  sentence_ids: string[];
  highlight: boolean;
  sense_id: string | null;
  ko_span: string | null;
  full_form_en?: string | null;
};
export type DisplaySense = {
  sense_id: string;
  canonical_ko: string | null;
  definition_kind: string;
  review_status: string;
  ai_review_status: string;
};
export type PreviewInput = {
  paper: { sentences: Sentence[]; glossary: Glossary[] };
  senses: DisplaySense[];
  showAiReviewedTerms: boolean;
  assumeApproved?: boolean;
};
export type Highlight = {
  start: number;
  end: number;
  label: string;
  idx: number;
};
export type PreviewProjection = {
  en: Record<string, Highlight[]>;
  ko: Record<string, Highlight[]>;
  terms: (Glossary & { term_ko: string | null; term_ko_span: string | null })[];
};
export function latexDisplay(s: string): string {
  return s
    .replace(/\\([%_&#$])/g, "$1")
    .replace(/(?<=\d)\s*\\times\s*(?=\d)/g, "×")
    .replace(/(?<=\d)\s*\\times\b/g, "×")
    .replace(/~|\\,/g, " ");
}
export function normalizeTerm(s: string): string {
  return s.toLowerCase().replace(/-/g, " ").replace(/\s+/gu, " ").trim();
}
export function termVariants(s: string): string[] {
  const n = normalizeTerm(s);
  const singular = n.endsWith("ies")
    ? n.slice(0, -3) + "y"
    : n.endsWith("s") && !n.endsWith("ss")
      ? n.slice(0, -1)
      : n;
  return [...new Set([n, singular])];
}
const ascii = /[A-Za-z0-9]/;
const hangul = /[가-힣]/;
/** 앱 lib/features/common/term_text.dart findTerm과 같은 규칙: 영문 표기는 앞뒤가 영문·숫자가 아닐 때만(RAG ≠ RAGAS),
 * 한글 표기는 앞이 한글이 아닐 때만(뒤에는 조사가 붙는다). 위치는 Dart처럼 UTF-16 기준. */
export function findTerm(text: string, label: string, from = 0): number {
  if (!label) return -1;
  const asciiStart = ascii.test(label[0]);
  const asciiEnd = ascii.test(label[label.length - 1]);
  const hangulStart = hangul.test(label[0]);
  for (let at = text.indexOf(label, from); at >= 0; at = text.indexOf(label, at + 1)) {
    const before = at > 0 ? text[at - 1] : "";
    const after = at + label.length < text.length ? text[at + label.length] : "";
    if (asciiStart && before && ascii.test(before)) continue;
    if (asciiEnd && after && ascii.test(after)) continue;
    if (hangulStart && before && hangul.test(before)) continue;
    return at;
  }
  return -1;
}
/** 같은 규칙으로 센 등장 횟수(검수 화면의 「n회 일치」). */
export function countTerm(text: string, label: string): number {
  let n = 0;
  for (let at = findTerm(text, label); at >= 0; at = findTerm(text, label, at + label.length)) n++;
  return n;
}
const stripParen = (s: string) => s.replace(/\s*\(.*\)$/, "");
/** 앱 GlossaryTerm.koreanLabels: 번역문 표기 → 사전 대응어 → 영문 그대로(SFT·VLM은 번역문에 남는다). 2자 이상만. */
export function koreanLabels(term: {
  term: string;
  term_ko: string | null;
  term_ko_span: string | null;
}): string[] {
  return [
    ...new Set(
      [term.term_ko_span, term.term_ko, term.term]
        .filter((l): l is string => l !== null)
        .map(stripParen),
    ),
  ].filter((l) => l.length >= 2);
}
/** 앱 리더 firstHighlights와 같은 결과(2026-10-29 앱 ed02106 기준).
 * - 한국어: 정의가 있는 모든 용어. 사전 연결·승인과 상관없이 번역문 표기(ko_span)를 쓰고(get_paper가 그대로 내보낸다),
 *   없으면 앱에 보일 수 있는 대응어, 그다음 영문 표기 순으로 찾는다.
 * - 영어: highlight=true이고 정의가 있는 용어만.
 * - 용어마다 연결 문장을 순서대로 보고, 처음 찾은 곳에서 멈춘다(겹치면 그 용어는 강조하지 않는다). */
export function projectPaperForPreview(input: PreviewInput): PreviewProjection {
  const terms = [...input.paper.glossary]
    .sort((a, b) => a.idx - b.idx)
    .map((term) => {
      const sense = input.senses.find((s) => s.sense_id === term.sense_id);
      const visible =
        sense &&
        sense.definition_kind !== "source_machine_translation_verbatim" &&
        (input.assumeApproved ||
          sense.review_status === "approved" ||
          (input.showAiReviewedTerms &&
            sense.ai_review_status === "first_pass_complete" &&
            sense.review_status === "pending"));
      const term_ko = visible ? sense.canonical_ko || null : null;
      return { ...term, term_ko, term_ko_span: term.ko_span || null };
    });
  const sentences = [...input.paper.sentences].sort(
    (a, b) => a.start_offset - b.start_offset,
  );
  const match = (korean: boolean): Record<string, Highlight[]> => {
    const out: Record<string, Highlight[]> = {};
    for (const term of terms) {
      if (!term.definition_ko || (!korean && !term.highlight)) continue;
      const labels = korean ? koreanLabels(term) : [term.term];
      found: for (const sentence of sentences.filter(
        (s) => s.kind === "text" && term.sentence_ids.includes(s.id),
      )) {
        const text = korean
          ? (sentence.translation ?? "")
          : latexDisplay(sentence.text);
        for (const label of labels) {
          const start = findTerm(text, label);
          if (start < 0) continue;
          const list = (out[sentence.id] ??= []);
          const end = start + label.length;
          if (list.every((h) => end <= h.start || start >= h.end))
            list.push({ start, end, label, idx: term.idx });
          break found; // Dart: 찾은 첫 자리에서 멈춘다(겹쳐도 뒤 문장을 다시 찾지 않는다)
        }
      }
    }
    for (const list of Object.values(out))
      list.sort((a, b) => a.start - b.start);
    return out;
  };
  return { en: match(false), ko: match(true), terms };
}
