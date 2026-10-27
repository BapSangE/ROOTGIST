-- 공식 소식: 짧은 원문 표시(thin)와 관련 소식(related). 수집은 worker/official_news.py.
-- thin: 원문이 피드 소개문 한 줄뿐이라(OpenAI) 요약 대신 소개문 번역만 있는 글. 앱은 「원문 소개문」으로 보여 준다.
-- related: 같은 실행에서 모은 소식 중 모델·제품 이름이 겹치는 글의 id(최대 3개).

alter table public.official_news
  add column thin boolean not null default false,
  add column related text[] not null default '{}';

create or replace function public.list_official_news(lim int default 60)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id, 'source', n.source, 'source_label', n.source_label, 'kind', n.kind, 'category', n.category,
    'title_en', n.title_en, 'title_ko', n.title_ko, 'url', n.url,
    'published_at', to_char(n.published_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'summary_ko', n.summary_ko, 'key_points', n.key_points, 'thin', n.thin, 'related', to_jsonb(n.related)
  ) order by n.published_at desc), '[]'::jsonb))
  from (
    select * from public.official_news
    where published_at > now() - interval '30 days'
    order by published_at desc
    limit least(greatest(lim, 1), 200)
  ) n;
$$;
