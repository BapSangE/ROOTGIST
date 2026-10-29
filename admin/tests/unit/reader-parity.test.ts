import { it, expect } from "vitest";
import {
  projectPaperForPreview,
  findTerm,
  countTerm,
  latexDisplay,
  normalizeTerm,
  termVariants,
} from "@/lib/domain/display";
const sense = {
  sense_id: "s1",
  canonical_ko: "고정 디코더",
  definition_kind: "ai_rewritten",
  review_status: "approved",
  ai_review_status: "first_pass_complete",
};
const row = {
  idx: 0,
  term: "frozen decoder",
  definition_ko: "가상 정의",
  sentence_ids: ["A01", "A02"],
  highlight: true,
  sense_id: "s1",
  ko_span: "동결된 디코더",
};
const paper = {
  sentences: [
    {
      id: "A01",
      kind: "text",
      start_offset: 0,
      text: "A frozen decoder and frozen decoder.",
      translation: "동결된 디코더와 동결된 디코더.",
    },
    {
      id: "A02",
      kind: "text",
      start_offset: 50,
      text: "frozen decoder",
      translation: "동결된 디코더",
    },
  ],
  glossary: [row],
};
it("uses actual ko_span once per term, never every matching occurrence", () => {
  const p = projectPaperForPreview({
    paper,
    senses: [sense],
    showAiReviewedTerms: false,
  });
  expect(p.ko.A01.map((x) => [x.start, x.label])).toEqual([
    [0, "동결된 디코더"],
  ]);
  expect(p.ko.A02).toBeUndefined();
  expect(p.en.A01.map((x) => x.label)).toEqual(["frozen decoder"]);
});
it("an empty ko_span is mapped through RPC nullif fallback, distinct from a missing displayable sense", () => {
  const p = projectPaperForPreview({
    paper: { ...paper, glossary: [{ ...row, ko_span: "" }] },
    senses: [sense],
    showAiReviewedTerms: false,
  });
  expect(p.ko).toEqual({});
  expect(p.terms[0].term_ko_span).toBeNull();
  expect(p.terms[0].term_ko).toBe("고정 디코더");
});
it("does not search later sentences when the first occurrence overlaps an earlier term", () => {
  const p = projectPaperForPreview({
    paper: { ...paper, glossary: [row, { ...row, idx: 1, term: "decoder" }] },
    senses: [sense],
    showAiReviewedTerms: false,
  });
  expect(p.en.A01).toHaveLength(1);
  expect(p.en.A02).toBeUndefined();
});
it("highlight false only suppresses English, and source translation verbatim is never displayed", () => {
  const p = projectPaperForPreview({
    paper: { ...paper, glossary: [{ ...row, highlight: false }] },
    senses: [sense],
    showAiReviewedTerms: false,
  });
  expect(p.en).toEqual({});
  expect(p.ko.A01).toHaveLength(1);
  const forbidden = projectPaperForPreview({
    paper,
    senses: [
      { ...sense, definition_kind: "source_machine_translation_verbatim" },
    ],
    showAiReviewedTerms: true,
    assumeApproved: true,
  });
  // 대응어(기계 번역 원문)는 숨기지만, 우리 번역문 속 표기(ko_span)는 앱이 강조한다(get_paper 2026-10-29)
  expect(forbidden.terms[0].term_ko).toBeNull();
  expect(forbidden.ko.A01.map((x) => x.label)).toEqual(["동결된 디코더"]);
});
it("pending AI terms follow app_config for the dictionary label only", () => {
  const pending = { ...sense, review_status: "pending" };
  const bare = { ...paper, glossary: [{ ...row, ko_span: null }], sentences: [{ ...paper.sentences[0], translation: "고정 디코더를 쓴다." }] };
  const hidden = projectPaperForPreview({ paper: bare, senses: [pending], showAiReviewedTerms: false });
  expect(hidden.terms[0].term_ko).toBeNull();
  expect(hidden.ko).toEqual({});
  expect(
    projectPaperForPreview({ paper: bare, senses: [pending], showAiReviewedTerms: true }).ko.A01,
  ).toHaveLength(1);
});
it("matches the app: unlinked terms by span or English left in the translation, word boundaries", () => {
  const p = projectPaperForPreview({
    paper: {
      sentences: [
        { id: "A01", kind: "text", start_offset: 0, text: "We apply SFT and RAG.", translation: "RAGAS로 평가하고 SFT를 적용한다." },
      ],
      glossary: [
        { idx: 0, term: "SFT", definition_ko: "정의", sentence_ids: ["A01"], highlight: true, sense_id: null, ko_span: null },
        { idx: 1, term: "RAG", definition_ko: "정의", sentence_ids: ["A01"], highlight: true, sense_id: null, ko_span: null },
      ],
    },
    senses: [],
    showAiReviewedTerms: false,
  });
  expect(p.ko.A01.map((x) => [x.label, x.start])).toEqual([["SFT", "RAGAS로 평가하고 ".length]]);
  expect(p.en.A01.map((x) => x.label)).toEqual(["SFT", "RAG"]);
});
it("finds Korean labels only at a word start and counts with the same rule", () => {
  expect(findTerm("멀티에이전트 구조", "에이전트")).toBe(-1);
  expect(findTerm("에이전트용 모델", "에이전트")).toBe(0);
  expect(countTerm("RAG와 RAG, RAGAS", "RAG")).toBe(2);
});
it("strips parenthetical suffix and uses UTF-16 ranges after emoji like Dart", () => {
  const p = projectPaperForPreview({
    paper: {
      sentences: [
        {
          ...paper.sentences[0],
          translation: "🧪 동결된 디코더는 그대로예요.",
        },
      ],
      glossary: [{ ...row, ko_span: "동결된 디코더 (가상)" }],
    },
    senses: [sense],
    showAiReviewedTerms: false,
  });
  expect(p.ko.A01[0].start).toBe(3);
  expect(p.ko.A01[0].label).toBe("동결된 디코더");
});
it("preserves app LaTeX conversion and worker plural variant semantics", () => {
  expect(latexDisplay("3 \\times 4~10\\times faster \\% \\_ \\,")).toBe(
    "3×4 10× faster % _  ",
  );
  expect(normalizeTerm("  Frozen--Decoder  ")).toBe("frozen decoder");
  expect(termVariants("policies")).toEqual(["policies", "policy"]);
  expect(termVariants("loss")).toEqual(["loss"]);
});
