-- GitHub 칸의 기간별 순위(2026-11-10): 일간(최근 24시간)·주간(7일)·월간(30일) 안에 생긴 AI 저장소를 별 많은 순으로.
-- 수집은 worker/official_news.py gh_rankings. 배치마다 받은 기간의 순위를 통째로 바꾼다(trending_models와 같은 방식).
-- period_start·period_end: 그 순위가 「언제부터 언제 사이에 생긴 저장소」인지. 앱이 그대로 보여 준다.
-- 쓰기는 배치 워커(비밀 키)만, 앱은 list_github_rankings로 읽는다.

create table public.github_rankings (
  id text primary key,                        -- 기간:소유자/이름 (예 week:JosssphZhou/poki)
  period text not null check (period in ('day', 'week', 'month')),
  rank smallint not null,
  full_name text not null,
  url text not null,
  description_en text,
  description_ko text,                        -- 저장소 설명을 AI가 옮긴 것(없으면 원문만)
  language text,
  stars integer not null default 0,           -- 모은 시각(collected_at)의 별 수
  forks integer not null default 0,
  created_at timestamptz,                     -- 저장소가 생긴 시각
  period_start timestamptz not null,
  period_end timestamptz not null,
  collected_at timestamptz not null default now()
);
create index github_rankings_period_rank on public.github_rankings (period, rank);

alter table public.github_rankings enable row level security;

create function public.list_github_rankings()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'collected_at', to_char(max(r.collected_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'periods', coalesce((
      select jsonb_object_agg(p.period, p.body) from (
        select g.period, jsonb_build_object(
          'start', to_char(min(g.period_start) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'end', to_char(max(g.period_end) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'repos', jsonb_agg(jsonb_build_object(
            'rank', g.rank, 'full_name', g.full_name, 'url', g.url,
            'description_en', g.description_en, 'description_ko', g.description_ko,
            'language', g.language, 'stars', g.stars, 'forks', g.forks,
            'created_at', to_char(g.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
          ) order by g.rank)
        ) as body
        from public.github_rankings g
        group by g.period
      ) p
    ), '{}'::jsonb))
  from public.github_rankings r;
$$;

revoke execute on function public.list_github_rankings() from public;
grant execute on function public.list_github_rankings() to anon, authenticated, service_role;
