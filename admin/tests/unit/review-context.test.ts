import { expect, it } from "vitest";
import { fixtureSnapshot } from "@/lib/server/fixtures";
import { termDetail } from "@/lib/server/read-models";
import { reviewContext } from "@/lib/domain/review-context";
function input() {
  return structuredClone(
    termDetail(
      fixtureSnapshot(),
      "occurrence",
      JSON.stringify({ paper_id: "0000.00001", idx: 0 }),
    ).value,
  );
}
it("separates literal matches from actual highlights in the selected sentence", () => {
  const d = input();
  const p = d.papers[0];
  p.sentences = [
    {
      id: "A01",
      kind: "text",
      start_offset: 0,
      text: "frozen decoder",
      translation: "동결된 디코더와 동결된 디코더",
    },
    {
      id: "A02",
      kind: "text",
      start_offset: 100,
      text: "frozen decoder",
      translation: "동결된 디코더",
    },
  ];
  p.glossary[0].sentence_ids = ["A01", "A02"];
  p.glossary[0].ko_span = "동결된 디코더";
  expect(reviewContext(d, { sentenceId: "A01" })).toMatchObject({
    matchCount: 2,
    appliedCount: 1,
  });
  expect(reviewContext(d, { sentenceId: "A02" })).toMatchObject({
    matchCount: 1,
    appliedCount: 0,
  });
});
it("keeps null/empty span fallback aligned with the existing projection", () => {
  const d = input();
  const p = d.papers[0];
  p.sentences = [
    {
      id: "A02",
      kind: "text",
      start_offset: 0,
      text: "frozen decoder",
      translation: "고정 디코더는 그대로",
    },
  ];
  p.glossary[0].sentence_ids = ["A02"];
  expect(reviewContext(d, { span: "" })).toMatchObject({
    span: "",
    label: "고정 디코더",
    matchCount: 1,
    appliedCount: 1,
  });
  expect(reviewContext(d, { span: null })).toMatchObject({
    span: null,
    label: "고정 디코더",
    matchCount: 1,
    appliedCount: 1,
  });
});
it("uses the real AI display setting and never assumes forbidden definitions are visible", () => {
  const d = input();
  d.papers[0].sentences = [
    {
      id: "A02",
      kind: "text",
      start_offset: 0,
      text: "frozen decoder",
      translation: "고정 디코더",
    },
  ];
  d.papers[0].glossary[0].sentence_ids = ["A02"];
  // 번역문 표기가 없으면 사전 대응어로 찾는데, 대응어는 승인·표시 설정을 따른다
  d.papers[0].glossary[0].ko_span = null;
  const sense = d.all_senses.find((s) => s.sense_id === d.sense?.sense_id)!;
  sense.canonical_ko = "고정 디코더";
  sense.review_status = "pending";
  sense.ai_review_status = "first_pass_complete";
  d.show_ai_reviewed_terms = false;
  expect(reviewContext(d, {}).appliedCount).toBe(0);
  expect(reviewContext(d, {}).inspection.ko).toHaveLength(1);
  d.show_ai_reviewed_terms = true;
  expect(reviewContext(d, {}).appliedCount).toBe(1);
  sense.definition_kind = "source_machine_translation_verbatim";
  expect(reviewContext(d, { assumeApproved: true }).appliedCount).toBe(0);
  // 번역문 표기(ko_span)는 우리 번역문의 글자라 승인과 상관없이 강조된다(앱 ed02106)
  expect(reviewContext(d, { span: "고정 디코더" }).appliedCount).toBe(1);
});
it("handles no linked paper and no translation without manufacturing context", () => {
  const d = input();
  d.papers = [];
  expect(reviewContext(d, {})).toMatchObject({
    paper: undefined,
    sentence: undefined,
    projection: null,
    matchCount: 0,
    appliedCount: 0,
  });
  const e = input();
  e.papers[0].sentences.forEach((s) => (s.translation = null));
  expect(reviewContext(e, {}).matchCount).toBe(0);
});
it("does not mutate source data while previewing a different span", () => {
  const d = input(),
    before = JSON.stringify(d);
  reviewContext(d, { span: "동결", assumeApproved: true });
  expect(JSON.stringify(d)).toBe(before);
});

it("can locate a selected label even when an earlier glossary item owns the actual highlight", () => {
  const d = input();
  const p = d.papers[0];
  const g = { ...p.glossary[0], ko_span: "고정 디코더", sentence_ids: ["A02"] };
  p.sentences = [
    {
      id: "A02",
      kind: "text",
      start_offset: 0,
      text: "frozen decoder",
      translation: "고정 디코더",
    },
  ];
  p.glossary = [
    { ...g, idx: 0 },
    { ...g, idx: 1 },
  ];
  d.row.idx = 1;
  d.row.id = JSON.stringify({ paper_id: p.id, idx: 1 });
  const c = reviewContext(d, {});
  expect(c.matchCount).toBe(1);
  expect(c.appliedCount).toBe(0);
  expect(c.inspection.ko).toHaveLength(1);
});
it("opens the first linked sentence that actually mentions the term", () => {
  const d = input();
  const p = d.papers[0];
  p.sentences = [
    { id: "A01", kind: "text", start_offset: 0, text: "A login screen after a tap.", translation: "탭한 뒤 로그인 화면." },
    { id: "A02", kind: "text", start_offset: 50, text: "the frozen decoder holds", translation: "동결된 디코더가 유지된다" },
  ];
  p.glossary[0].sentence_ids = ["A01", "A02"];
  p.glossary[0].ko_span = "동결된 디코더";
  const ctx = reviewContext(d, {});
  expect(ctx.sentence?.id).toBe("A02");
  expect([...ctx.withoutTerm]).toEqual(["A01"]);
  expect(reviewContext(d, { sentenceId: "A01" }).sentence?.id).toBe("A01"); // 직접 고르면 그대로
});
