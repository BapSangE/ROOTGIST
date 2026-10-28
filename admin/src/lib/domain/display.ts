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
      return {
        ...term,
        term_ko,
        term_ko_span: term_ko ? term.ko_span || null : null,
      };
    });
  const sentences = [...input.paper.sentences].sort(
    (a, b) => a.start_offset - b.start_offset,
  );
  const match = (korean: boolean): Record<string, Highlight[]> => {
    const out: Record<string, Highlight[]> = {};
    for (const term of terms) {
      if (!term.definition_ko || (korean ? !term.term_ko : !term.highlight))
        continue;
      const label = korean
        ? (term.term_ko_span ?? term.term_ko!).replace(/\s*\(.*\)$/, "")
        : term.term;
      if (!label) continue;
      for (const sentence of sentences.filter(
        (s) => s.kind === "text" && term.sentence_ids.includes(s.id),
      )) {
        const start = (
          korean ? (sentence.translation ?? "") : latexDisplay(sentence.text)
        ).indexOf(label);
        if (start < 0) continue;
        const list = (out[sentence.id] ??= []);
        const end = start + label.length;
        if (list.every((h) => end <= h.start || start >= h.end))
          list.push({ start, end, label, idx: term.idx });
        break; // Dart does not retry an overlapping term in later sentences.
      }
    }
    for (const list of Object.values(out))
      list.sort((a, b) => a.start - b.start);
    return out;
  };
  return { en: match(false), ko: match(true), terms };
}
