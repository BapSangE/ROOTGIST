-- 개발자 화제 GitHub에 생긴 지 2주 가까운 저장소가 남던 문제(2026-11-06).
-- 직전 마이그레이션(20261106120000)은 「최근 7일 안에 고른」 저장소를 돌려줘, 지난주에 고른 저장소가 생긴 지 열흘이 넘어도 보였다.
-- 앱 문구 「이번 주 새 AI 도구」에 맞춰 생긴 지 10일 안(published_at = 저장소 생성일)인 것만 남긴다. 나머지는 그대로.
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
      where kind = 'hot' and source = 'github' and collected_at > now() - interval '7 days'
        and published_at > now() - interval '10 days'
      order by collected_at desc, points desc nulls last limit 20)
  ) n;
$$;
