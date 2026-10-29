import type { TermDetail } from "./contracts";
import { normalizeTerm, projectPaperForPreview, latexDisplay } from "./display";
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
  const label = (span || sense?.canonical_ko || row.canonical_ko || "").replace(
    /\s*\(.*\)$/,
    "",
  );
  const matchCount =
    label && sentence?.translation
      ? sentence.translation.split(label).length - 1
      : 0;
  const appliedCount =
    sentence && glossary
      ? (projection?.ko[sentence.id] ?? []).filter(
          (h) => h.idx === glossary.idx,
        ).length
      : 0;
  function locate(text: string, term: string) {
    const start = term ? text.indexOf(term) : -1;
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
    projection,
    matchCount,
    appliedCount,
    inspection,
  };
}
