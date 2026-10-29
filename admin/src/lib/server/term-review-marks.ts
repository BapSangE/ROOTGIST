import type { ReviewMarks } from "@/lib/domain/contracts";
import { normalizeTerm } from "@/lib/domain/display";

/** 목록·상세의 검수 상태: 적용 위치는 검수 기록(같은 용어일 때만), 의미·후보는 원본 review_status를 그대로 쓴다. */
export function reviewedAt(marks: ReviewMarks | undefined, paperId: string, idx: number, term: string): string | null {
  return marks?.occurrences.find((o) => o.paper_id === paperId && o.idx === idx && o.term === term)?.reviewed_at ?? null;
}
export function controlNote(marks: ReviewMarks | undefined, kind: string, key: string) {
  return marks?.controls.find((c) => c.entity_type === kind && c.entity_key === (kind === "candidate" ? normalizeTerm(key) : key)) ?? null;
}
