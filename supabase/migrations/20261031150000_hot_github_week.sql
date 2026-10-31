-- 개발자 화제의 GitHub가 1개뿐이던 문제(2026-10-31). 수집기(from_github)는 최근 7일 안에 생긴 저장소를 별 순 5개 모으는데,
-- 이 함수가 화제를 published_at(저장소 생성일) 3일 안으로만 돌려줘 3~7일 전에 생긴 저장소는 앱에 닿지 않았다.
-- Hacker News(수집 36시간)는 3일 그대로, GitHub는 앱 문구 「이번 주 새 AI 도구」에 맞춰 8일로 따로 센다.
-- 점수 단위도 달라(HN 추천 수 · GitHub 별 수) 한 줄로 섞어 자르지 않고 각자 상한을 둔다.
create or replace function public.list_official_news(lim int default 60)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id, 'source', n.source, 'source_label', n.source_label, 'kind', n.kind, 'category', n.category,
    'title_en', n.title_en, 'title_ko', n.title_ko, 'url', n.url,
    'published_at', to_char(n.published_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'summary_ko', n.summary_ko, 'key_points', n.key_points, 'thin', n.thin, 'related', to_jsonb(n.related),
    'points', n.points, 'comments', n.comments, 'discussion_url', n.discussion_url
  ) order by n.published_at desc), '[]'::jsonb))
  from (
    (select * from public.official_news
      where kind <> 'hot' and published_at > now() - interval '30 days'
      order by published_at desc limit least(greatest(lim, 1), 200))
    union all
    (select * from public.official_news
      where kind = 'hot' and source <> 'github' and published_at > now() - interval '3 days'
      order by points desc nulls last limit 40)
    union all
    (select * from public.official_news
      where kind = 'hot' and source = 'github' and published_at > now() - interval '8 days'
      order by points desc nulls last limit 10)
  ) n;
$$;
