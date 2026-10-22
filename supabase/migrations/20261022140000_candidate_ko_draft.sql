-- 자체 축적 후보의 한국어 대응어 AI 초안. 검토자는 승인만 하거나(초안 채택) canonical_ko에 고쳐 쓴다.
-- 사전으로 옮길 때 canonical_ko가 있으면 그것, 없으면 초안을 쓴다. 승인 전 초안은 앱에 나가지 않는다.
alter table public.term_candidates
  add column canonical_ko_draft text,
  add column draft_model text;
