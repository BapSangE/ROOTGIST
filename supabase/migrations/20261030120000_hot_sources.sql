-- 개발자 화제(Hacker News·GitHub 새 AI 도구, 2026-10-30). 수집은 worker/official_news.py from_hn·from_github.
-- kind=hot: 공식 발표가 아닌 화제 글. points = HN 점수 또는 GitHub 별 수, comments = HN 댓글 수, discussion_url = HN 토론 주소.
-- 공식 소식이 같은 글을 다루면 화제로 따로 두지 않고 그 소식의 points·comments·discussion_url에 HN 반응을 붙인다.

alter table public.official_news drop constraint official_news_kind_check;
alter table public.official_news add constraint official_news_kind_check check (kind in ('post', 'notice', 'release', 'hot'));
alter table public.official_news
  add column points integer,
  add column comments integer,
  add column discussion_url text;

-- 공식 소식(최근 30일, lim개)과 화제(최근 3일, 최대 40개)를 따로 세어 합친다: 화제가 하루 20개씩 쌓여도 공식 소식을 밀어내지 않게.
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
      where kind = 'hot' and published_at > now() - interval '3 days'
      order by points desc nulls last limit 40)
  ) n;
$$;
