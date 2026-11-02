-- 탐색 소식이 최근 2주쯤에서 끊기던 문제(2026-11-02). 앱이 lim 60을 보내 발표·업데이트가 60건(약 2주)에서 잘렸고,
-- 날짜 묶음(하루 → 주 → 달)의 지난주·지난달 묶음이 거의 비었다. 종류별로 나눠 받는다(사용자 결정):
-- 발표·업데이트는 최근 90일·최대 400건(한 건 약 1KB, 90일치 약 350KB), 개발자 화제는 그대로 HN 3일·GitHub 8일.
-- 더 쌓이면 next_cursor로 이어 받기를 붙인다.
create or replace function public.list_official_news(lim int default 400)
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
      where kind <> 'hot' and published_at > now() - interval '90 days'
      order by published_at desc limit least(greatest(lim, 1), 400))
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
