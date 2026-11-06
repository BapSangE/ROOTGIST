-- 개발자 화제의 GitHub가 며칠 전 저장소로만 채워지던 문제(2026-11-06).
-- 이 함수는 GitHub를 「생긴 지 8일 안(published_at = 저장소 생성일), 별 많은 순 10개」로 돌려줬다. 수집기가 고르는 기준을
-- 별 총합에서 뜨는 속도로 바꿔도, 지난주 별 7천 개짜리 저장소가 계속 위 10개를 차지해 새로 고른 저장소가 앱에 닿지 않는다.
-- 그래서 수집기가 「최근 7일 안에 고른」 저장소(collected_at: 고를 때마다 새로 적힌다)를 최근에 고른 순으로 돌려준다.
-- 날마다 고른 5개가 일주일 남아 목록이 날짜로 이어진다. 나머지(발표·업데이트·Hacker News)는 그대로.
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
      order by collected_at desc, points desc nulls last limit 20)
  ) n;
$$;
