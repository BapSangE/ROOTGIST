import type { TermDetail } from "./contracts";
import {
  normalizeTerm,
  projectPaperForPreview,
  latexDisplay,
  findTerm,
  countTerm,
  koreanLabels,
} from "./display";
export type ReviewOptions = {
  paperId?: string | null;
  sentenceId?: string | null;
  span?: string | null;
  assumeApproved?: boolean;
};
/** Derive display state only; the source snapshot is never edited. */
export function reviewContext(
  value: TermDetail["value"],
  options: ReviewOptions,
) {
  const { row, papers, sense, all_senses, show_ai_reviewed_terms } = value;
  const paper = papers.find((p) => p.id === options.paperId) ?? papers[0];
  const glossary = paper?.glossary.find((g) =>
    row.type === "occurrence"
      ? g.idx === row.idx
      : row.type === "sense"
        ? g.sense_id === row.sense_id
        : normalizeTerm(g.term) === row.id,
  );
  const texts = paper?.sentences.filter((s) => s.kind === "text") ?? [];
  const sentence =
    texts.find((s) => s.id === options.sentenceId) ??
    texts.find((s) => glossary?.sentence_ids.includes(s.id)) ??
    texts[0];
  const span =
    options.span !== undefined ? options.span : (glossary?.ko_span ?? null);
  const projected =
    paper && glossary
      ? {
          ...paper,
          glossary: paper.glossary.map((g) =>
            g.idx === glossary.idx ? { ...g, ko_span: span } : g,
          ),
        }
      : paper;
  const projection = projected
    ? projectPaperForPreview({
        paper: projected,
        senses: all_senses,
        showAiReviewedTerms: show_ai_reviewed_terms,
        assumeApproved: options.assumeApproved,
      })
    : null;
  // 앱과 같은 순서의 후보 표기(번역문 표기 → 보이는 대응어 → 영문) 중 이 문장에 실제로 있는 첫 표기.
  // 하나도 없으면 첫 후보를 보여 「표기 일치 없음」으로 알린다.
  const projectedTerm = projection?.terms.find((t) => t.idx === glossary?.idx);
  // 검토용 찾기는 앱에 아직 안 보이는 사전 표기(미승인 대응어)도 뒤에 붙여 찾는다(앱 표시는 projection이 따로 판단)
  const labels = [
    ...new Set([
      ...(projectedTerm ? koreanLabels(projectedTerm) : []),
      ...[span, sense?.canonical_ko, row.canonical_ko, row.term]
        .filter((l): l is string => !!l)
        .map((l) => l.replace(/\s*\(.*\)$/, "")),
    ]),
  ];
  const translation = sentence?.translation ?? "";
  const label =
    labels.find((l) => findTerm(translation, l) >= 0) ?? labels[0] ?? "";
  const matchCount = label && translation ? countTerm(translation, label) : 0;
  const appliedCount =
    sentence && glossary
      ? (projection?.ko[sentence.id] ?? []).filter(
          (h) => h.idx === glossary.idx,
        ).length
      : 0;
  function locate(text: string, term: string) {
    const start = term ? findTerm(text, term) : -1;
    return start < 0
      ? []
      : [
          {
            start,
            end: start + term.length,
            label: term,
            idx: glossary?.idx ?? 0,
          },
        ];
  }
  const inspection = {
    en: locate(latexDisplay(sentence?.text ?? ""), glossary?.term ?? row.term),
    ko: locate(sentence?.translation ?? "", label),
  };
  return {
    paper,
    glossary,
    sentence,
    texts,
    span,
    label,
    labels,
    projection,
    matchCount,
    appliedCount,
    inspection,
  };
}
