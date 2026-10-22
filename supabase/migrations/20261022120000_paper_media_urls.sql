-- HF가 주는 이미지·첨부 자료 주소만 저장한다. 화면에는 쓰지 않는다(HANDOFF 1장 제외 항목, A8 권리 검토 전).
-- 읽기 함수(get_digest·get_paper)도 이 칸을 돌려주지 않는다.
alter table public.papers
  add column thumbnail_url text,                    -- 최상위 thumbnail(HF 공유용 이미지)
  add column media_urls text[] not null default '{}'; -- paper.mediaUrls(올린 사람이 붙인 그림·동영상)
